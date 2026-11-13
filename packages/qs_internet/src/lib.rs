//! Quick Send: transfers between devices on different networks (mobile data,
//! another Wi-Fi, …) over iroh.
//!
//! The sender imports the files into a temporary blob store, publishes them as
//! one iroh-blobs collection and returns a ticket (an `iroh-blobs` BlobTicket:
//! the sender's endpoint id + addresses + the collection hash). The receiver
//! dials the sender by that id: iroh tries a direct QUIC connection (UDP hole
//! punching) and otherwise relays the encrypted QUIC stream through an iroh
//! relay server. Data is verified with BLAKE3 while it streams, and an
//! interrupted download resumes from the blocks already stored.
//!
//! Tickets are capabilities: whoever has one can download the files while the
//! sender keeps sharing. Tickets use the same format as `sendme`.
//!
//! This crate knows nothing about the local-network (LocalSend protocol) path.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::sync::Arc;

use anyhow::{Context, Result, anyhow, bail};
use futures_util::StreamExt;
use iroh::endpoint::presets;
use iroh::protocol::Router;
use iroh::{Endpoint, RelayMode, RelayUrl};
use iroh_blobs::api::blobs::{AddPathOptions, ImportMode};
use iroh_blobs::api::downloader::DownloadProgressItem;
use iroh_blobs::format::collection::Collection;
use iroh_blobs::provider::events::{EventMask, EventSender, ProviderMessage, RequestMode, RequestUpdate};
use iroh_blobs::store::fs::FsStore;
use iroh_blobs::ticket::BlobTicket;
use iroh_blobs::{BlobFormat, BlobsProtocol, HashAndFormat};
use serde_json::{Value, json};
use tokio_util::sync::CancellationToken;

/// Receives progress events as JSON objects (`{"type": "...", ...}`).
pub type EventFn = Arc<dyn Fn(Value) + Send + Sync + 'static>;

/// Relay servers: iroh's public relays unless a build sets QS_IROH_RELAY to an own relay URL.
fn relay_mode() -> RelayMode {
    match option_env!("QS_IROH_RELAY").filter(|v| !v.is_empty()) {
        Some(url) => match RelayUrl::from_str(url) {
            Ok(url) => RelayMode::custom([url]),
            Err(_) => RelayMode::Default,
        },
        None => RelayMode::Default,
    }
}

async fn endpoint() -> Result<Endpoint> {
    Endpoint::builder(presets::N0)
        .relay_mode(relay_mode())
        .bind()
        .await
        .context("could not open the network endpoint")
}

/// The ranges `get_hash_seq_and_sizes` requests: the whole list, the last chunk of every file.
fn size_probe_ranges() -> iroh_blobs::protocol::ChunkRangesSeq {
    use iroh_blobs::protocol::{ChunkRanges, ChunkRangesExt, ChunkRangesSeq};
    ChunkRangesSeq::from_ranges_infinite([ChunkRanges::all(), ChunkRanges::last_chunk()])
}

/// One file to send: the name the receiver sees and where it is on disk.
#[derive(Debug, Clone)]
pub struct SendFile {
    pub name: String,
    pub path: PathBuf,
}

/// Keeps only a plain file name: no directories, no "..", no control characters.
pub fn safe_file_name(name: &str) -> String {
    let last = name.rsplit(['/', '\\']).next().unwrap_or("");
    let cleaned: String = last.chars().filter(|c| !c.is_control()).collect();
    let trimmed = cleaned.trim().trim_start_matches('.').trim();
    if trimmed.is_empty() { "file".to_string() } else { trimmed.chars().take(200).collect() }
}

/// "name (n).ext"
fn numbered(name: &str, n: u32) -> String {
    match name.rfind('.') {
        Some(i) if i > 0 => format!("{} ({n}){}", &name[..i], &name[i..]),
        _ => format!("{name} ({n})"),
    }
}

/// [name], or the first "name (n).ext" that is not taken yet; records the result in [used].
fn unique_name(name: String, used: &mut HashSet<String>) -> String {
    let mut candidate = name.clone();
    let mut n = 2;
    while used.contains(&candidate) {
        candidate = numbered(&name, n);
        n += 1;
    }
    used.insert(candidate.clone());
    candidate
}

/// Shares [files] until [cancel] fires. Emits:
/// `ticket {ticket, files, size}`, `peerConnected`, `sent {count}` (each completed download),
/// `error {message}`. [data_dir] holds the temporary blob store and is removed afterwards.
pub async fn send(files: Vec<SendFile>, data_dir: PathBuf, on_event: EventFn, cancel: CancellationToken) -> Result<()> {
    if files.is_empty() {
        bail!("nothing to send");
    }
    let data_dir = std::path::absolute(&data_dir)?;
    let _ = tokio::fs::remove_dir_all(&data_dir).await;
    let store = FsStore::load(&data_dir).await.context("could not create the temporary store")?;
    let result = send_inner(&store, files, on_event, cancel).await;
    let _ = store.shutdown().await;
    let _ = tokio::fs::remove_dir_all(&data_dir).await;
    result
}

async fn send_inner(store: &FsStore, files: Vec<SendFile>, on_event: EventFn, cancel: CancellationToken) -> Result<()> {
    let mut used = HashSet::new();
    let mut entries = Vec::new();
    let mut tags = Vec::new();
    let mut total = 0u64;
    for file in &files {
        let path = std::path::absolute(&file.path)?;
        total += tokio::fs::metadata(&path).await.with_context(|| format!("cannot read {}", path.display()))?.len();
        // Reference the file instead of copying it into the store (large videos stay where they are).
        let tag = store
            .blobs()
            .add_path_with_opts(AddPathOptions { path, format: BlobFormat::Raw, mode: ImportMode::TryReference })
            .temp_tag()
            .await?;
        entries.push((unique_name(safe_file_name(&file.name), &mut used), tag.hash()));
        tags.push(tag);
    }
    let collection: Collection = entries.into_iter().collect();
    let root = collection.store(store).await?;
    let root_hash = root.hash();

    let (events, mut rx) = EventSender::channel(32, EventMask { get: RequestMode::NotifyLog, ..EventMask::DEFAULT });
    let endpoint = endpoint().await?;
    let blobs = BlobsProtocol::new(store, Some(events));
    let router = Router::builder(endpoint).accept(iroh_blobs::ALPN, blobs).spawn();

    // Wait until a relay is reachable so the ticket carries a relay address, not only local ones.
    let _ = tokio::time::timeout(std::time::Duration::from_secs(10), router.endpoint().online()).await;
    let ticket = BlobTicket::new(router.endpoint().addr(), root_hash, BlobFormat::HashSeq);
    on_event(json!({"type": "ticket", "ticket": ticket.to_string(), "files": files.len(), "size": total}));

    let watcher = {
        let on_event = on_event.clone();
        tokio::spawn(async move {
            let completed = Arc::new(std::sync::atomic::AtomicU64::new(0));
            while let Some(msg) = rx.recv().await {
                if let ProviderMessage::GetRequestReceivedNotify(msg) = msg {
                    if msg.inner.request.hash != root_hash {
                        continue;
                    }
                    // The receiver first asks only for the file list and sizes (see receive()); that is not a download.
                    let probe = msg.inner.request.ranges == size_probe_ranges();
                    if probe {
                        on_event(json!({"type": "peerConnected"}));
                    }
                    let on_event = on_event.clone();
                    let completed = completed.clone();
                    let mut updates = msg.rx;
                    tokio::spawn(async move {
                        let mut done = false;
                        while let Ok(Some(update)) = updates.recv().await {
                            if let RequestUpdate::Completed(_) = update {
                                done = true;
                            }
                        }
                        // The update channel must be drained either way; dropping it aborts the request.
                        if done && !probe {
                            let count = completed.fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1;
                            on_event(json!({"type": "sent", "count": count}));
                        }
                    });
                }
            }
        })
    };

    cancel.cancelled().await;
    watcher.abort();
    router.shutdown().await.ok();
    drop(tags);
    Ok(())
}

/// Downloads the files of [ticket] into [dest_dir]. Emits `connecting`, `progress {done, total}`,
/// `received {files: [path…], size}`. Returns the saved paths. Cancel with [cancel].
pub async fn receive(ticket: &str, dest_dir: PathBuf, data_dir: PathBuf, on_event: EventFn, cancel: CancellationToken) -> Result<Vec<PathBuf>> {
    let ticket = BlobTicket::from_str(ticket.trim()).map_err(|_| anyhow!("invalid code"))?;
    if ticket.format() != BlobFormat::HashSeq {
        bail!("this code is not a Quick Send / sendme collection");
    }
    let dest_dir = std::path::absolute(&dest_dir)?;
    let data_dir = std::path::absolute(&data_dir)?;
    tokio::fs::create_dir_all(&data_dir).await?;
    let store = FsStore::load(&data_dir).await.context("could not create the temporary store")?;
    let result = tokio::select! {
        r = receive_inner(&store, &ticket, &dest_dir, on_event) => r,
        _ = cancel.cancelled() => Err(anyhow!("cancelled")),
    };
    let _ = store.shutdown().await;
    // Keep partial data after a failure, so a retry with the same code resumes; clear it after success.
    if result.is_ok() {
        let _ = tokio::fs::remove_dir_all(&data_dir).await;
    }
    result
}

async fn receive_inner(store: &FsStore, ticket: &BlobTicket, dest_dir: &Path, on_event: EventFn) -> Result<Vec<PathBuf>> {
    let endpoint = endpoint().await?;
    let result = receive_with(&endpoint, store, ticket, dest_dir, on_event).await;
    endpoint.close().await;
    result
}

async fn receive_with(endpoint: &Endpoint, store: &FsStore, ticket: &BlobTicket, dest_dir: &Path, on_event: EventFn) -> Result<Vec<PathBuf>> {
    on_event(json!({"type": "connecting"}));
    let provider = ticket.addr().clone();
    let connection = endpoint.connect(provider.clone(), iroh_blobs::ALPN).await.context("could not reach the sender")?;
    let (_, sizes) = iroh_blobs::get::request::get_hash_seq_and_sizes(&connection, &ticket.hash(), 1024 * 1024 * 32, None)
        .await
        .context("could not read the file list")?;
    let total: u64 = sizes.iter().sum();
    on_event(json!({"type": "progress", "done": 0, "total": total}));

    // A download can fail transiently (e.g. while the connection moves from the relay to a direct path).
    // The store keeps what arrived, so a retry only fetches the rest.
    let mut attempt = 0;
    loop {
        attempt += 1;
        match download_once(endpoint, store, ticket, total, &on_event).await {
            Ok(()) => break,
            Err(e) if attempt < 4 => {
                tracing_log(&format!("download attempt {attempt} failed: {e:#}"));
                tokio::time::sleep(std::time::Duration::from_secs(2)).await;
            }
            Err(e) => return Err(e),
        }
    }
    on_event(json!({"type": "progress", "done": total, "total": total}));

    let collection = Collection::load(ticket.hash(), &iroh_blobs::api::Store::from(store.clone())).await.context("could not read the file list")?;
    tokio::fs::create_dir_all(dest_dir).await?;
    let mut used = HashSet::new();
    let mut saved = Vec::new();
    for (name, hash) in collection.iter() {
        // Never overwrite files already in the destination.
        let base = safe_file_name(name);
        let mut file_name = base.clone();
        let mut n = 2;
        while used.contains(&file_name) || dest_dir.join(&file_name).exists() {
            file_name = numbered(&base, n);
            n += 1;
        }
        used.insert(file_name.clone());
        let target = dest_dir.join(&file_name);
        store.blobs().export(*hash, &target).await.with_context(|| format!("could not save {file_name}"))?;
        saved.push(target);
    }
    on_event(json!({"type": "received", "files": saved.iter().map(|p| p.to_string_lossy()).collect::<Vec<_>>(), "size": total}));
    Ok(saved)
}

async fn download_once(endpoint: &Endpoint, store: &FsStore, ticket: &BlobTicket, total: u64, on_event: &EventFn) -> Result<()> {
    let mut stream = store
        .downloader(endpoint)
        .download(HashAndFormat::hash_seq(ticket.hash()), Some(ticket.addr().id))
        .stream()
        .await?;
    let mut last = std::time::Instant::now();
    while let Some(item) = stream.next().await {
        match item {
            DownloadProgressItem::Progress(done) => {
                if last.elapsed().as_millis() >= 200 {
                    last = std::time::Instant::now();
                    on_event(json!({"type": "progress", "done": done.min(total), "total": total}));
                }
            }
            DownloadProgressItem::Error(e) => bail!("download failed: {e}"),
            DownloadProgressItem::DownloadError => bail!("download failed"),
            _ => {}
        }
    }
    Ok(())
}

fn tracing_log(message: &str) {
    eprintln!("qs_internet: {message}");
}

/// True when [text] parses as a collection ticket (used to validate pasted codes).
pub fn is_valid_ticket(text: &str) -> bool {
    BlobTicket::from_str(text.trim()).map(|t| t.format() == BlobFormat::HashSeq).unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_names_are_sanitized() {
        assert_eq!(safe_file_name("../../etc/passwd"), "passwd");
        assert_eq!(safe_file_name("dir\\evil.exe"), "evil.exe");
        assert_eq!(safe_file_name(".hidden"), "hidden");
        assert_eq!(safe_file_name(""), "file");
        assert_eq!(safe_file_name("a\u{0}b.txt"), "ab.txt");
    }

    #[test]
    fn duplicate_names_get_numbers() {
        let mut used = HashSet::new();
        assert_eq!(unique_name("a.txt".into(), &mut used), "a.txt");
        assert_eq!(unique_name("a.txt".into(), &mut used), "a (2).txt");
        assert_eq!(unique_name("a.txt".into(), &mut used), "a (3).txt");
    }

    #[test]
    fn rejects_garbage_tickets() {
        assert!(!is_valid_ticket("hello"));
        assert!(!is_valid_ticket(""));
    }

    /// Full send → receive round trip through the default relays (needs network; run with --ignored).
    #[tokio::test]
    #[ignore]
    async fn round_trip() -> Result<()> {
        let dir = std::env::temp_dir().join(format!("qs-internet-test-{}", std::process::id()));
        let src = dir.join("src");
        std::fs::create_dir_all(&src)?;
        std::fs::write(src.join("a.txt"), b"hello over iroh")?;
        std::fs::write(src.join("b.bin"), vec![7u8; 3 * 1024 * 1024])?;
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<Value>();
        let cancel = CancellationToken::new();
        let files = vec![
            SendFile { name: "a.txt".into(), path: src.join("a.txt") },
            SendFile { name: "../b.bin".into(), path: src.join("b.bin") },
        ];
        let sender = tokio::spawn(send(files, dir.join("send-store"), Arc::new(move |v| { let _ = tx.send(v); }), cancel.clone()));
        let ticket = loop {
            let v = rx.recv().await.context("sender stopped")?;
            if v["type"] == "ticket" { break v["ticket"].as_str().unwrap().to_string(); }
        };
        let saved = receive(&ticket, dir.join("out"), dir.join("recv-store"), Arc::new(|_| {}), CancellationToken::new()).await?;
        assert_eq!(saved.len(), 2);
        assert_eq!(std::fs::read(dir.join("out/a.txt"))?, b"hello over iroh");
        assert_eq!(std::fs::read(dir.join("out/b.bin"))?.len(), 3 * 1024 * 1024);
        cancel.cancel();
        sender.await??;
        std::fs::remove_dir_all(&dir).ok();
        Ok(())
    }
}

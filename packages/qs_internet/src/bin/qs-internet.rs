//! Quick Send desktop helper for transfers over the internet (iroh).
//! The Flutter app starts it and reads one JSON event per line from stdout.
//!
//!   qs-internet send --data-dir DIR FILE...
//!       Prints {"type":"ticket",...}, then "peerConnected"/"sent" events. Shares
//!       until stdin is closed or receives a "stop" line (the app quitting closes it).
//!   qs-internet receive --data-dir DIR --dest DIR CODE
//!       Prints "connecting", "progress", then "received" and exits 0.
//! Errors are printed as {"type":"error","message":...} and exit 1.

use std::io::{BufRead, Write};
use std::path::PathBuf;
use std::sync::Arc;

use qs_internet::{EventFn, SendFile};
use serde_json::{Value, json};
use tokio_util::sync::CancellationToken;

fn print(event: Value) {
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "{event}");
    let _ = out.flush();
}

fn usage() -> ! {
    print(json!({"type": "error", "message": "usage: qs-internet send --data-dir DIR FILE... | receive --data-dir DIR --dest DIR CODE"}));
    std::process::exit(2)
}

fn main() {
    // Diagnostics on stderr only when RUST_LOG is set (stdout carries the JSON events).
    if std::env::var_os("RUST_LOG").is_some() {
        tracing_subscriber::fmt().with_env_filter(tracing_subscriber::EnvFilter::from_default_env()).with_writer(std::io::stderr).init();
    }
    let mut args = std::env::args().skip(1);
    let command = args.next().unwrap_or_else(|| usage());
    let mut data_dir = None;
    let mut dest = None;
    let mut rest = Vec::new();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--data-dir" => data_dir = args.next().map(PathBuf::from),
            "--dest" => dest = args.next().map(PathBuf::from),
            _ => rest.push(arg),
        }
    }
    let data_dir = data_dir.unwrap_or_else(|| usage());
    let runtime = tokio::runtime::Runtime::new().expect("tokio runtime");
    let on_event: EventFn = Arc::new(print);
    let cancel = CancellationToken::new();

    // stdin closing (the app exited) or a "stop" line ends sharing / cancels a download.
    {
        let cancel = cancel.clone();
        std::thread::spawn(move || {
            for line in std::io::stdin().lock().lines() {
                match line {
                    Ok(l) if l.trim() == "stop" => break,
                    Ok(_) => continue,
                    Err(_) => break,
                }
            }
            cancel.cancel();
        });
    }

    let result = runtime.block_on(async {
        match command.as_str() {
            "send" => {
                if rest.is_empty() {
                    usage();
                }
                let files = rest
                    .iter()
                    .map(|p| {
                        let path = PathBuf::from(p);
                        let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| "file".into());
                        SendFile { name, path }
                    })
                    .collect();
                qs_internet::send(files, data_dir, on_event, cancel).await
            }
            "receive" => {
                let code = rest.first().cloned().unwrap_or_else(|| usage());
                let dest = dest.unwrap_or_else(|| usage());
                qs_internet::receive(&code, dest, data_dir, on_event, cancel).await.map(|_| ())
            }
            _ => usage(),
        }
    });
    if let Err(e) = result {
        print(json!({"type": "error", "message": format!("{e:#}")}));
        std::process::exit(1);
    }
}

use anyhow::{Context, Result, anyhow};
use futures_util::StreamExt;
use jni::objects::{GlobalRef, JClass, JIntArray, JObject, JString, JValue};
use jni::sys::{jboolean, jstring};
use jni::{JNIEnv, JavaVM};
use localsend::crypto::cert::{SelfSignedCert, generate_self_signed};
use localsend::discovery::{
    DeviceIdentity as DiscoveryIdentity, DiscoveredDevice, DiscoveryConfig, DiscoveryEvent,
    DiscoveryHandle, HttpChannel,
};
use localsend::http::client::LsHttpClientV2;
use localsend::http::dto_v2::{PrepareUploadRequestDtoV2, RegisterDtoV2};
use localsend::http::server::common::save::FileUploadTarget;
use localsend::http::server::v2::{PrepareUploadDecisionV2, ServerEventV2};
use localsend::http::server::web::WebConfig;
use localsend::http::server::{ServerConfigV2, ServerHandle, TlsConfig, start_with_port};
use localsend::http::state::ClientInfo;
use localsend::model::discovery::{DeviceType, PROTOCOL_VERSION_V2, ProtocolType};
use localsend::model::transfer::{FileContent, FileDto};
use localsend::multicast::{DEFAULT_MULTICAST_GROUP, DEFAULT_MULTICAST_GROUP_V6, MulticastDevice};
use localsend::util::interface::InterfaceFilter;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::{HashMap, HashSet};
use std::os::fd::{FromRawFd, IntoRawFd, OwnedFd};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};
use tokio::runtime::{Builder, Runtime};
use tokio::sync::{Mutex as AsyncMutex, mpsc, oneshot};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

const HTTP_PORT: u16 = localsend::multicast::DEFAULT_PORT;

#[derive(Clone, Serialize, Deserialize)]
pub struct Identity {
    pub private_key_pem: String,
    pub public_key_pem: String,
    pub certificate_pem: String,
    pub fingerprint: String,
}

impl From<SelfSignedCert> for Identity {
    fn from(value: SelfSignedCert) -> Self {
        Self {
            private_key_pem: value.private_key_pem,
            public_key_pem: value.public_key_pem,
            certificate_pem: value.certificate_pem,
            fingerprint: value.fingerprint,
        }
    }
}

struct Engine {
    callback: GlobalRef,
    identity: Identity,
    alias: String,
    visible: std::sync::atomic::AtomicBool,
    server: AsyncMutex<Option<Arc<ServerHandle>>>,
    discovery: AsyncMutex<Option<Arc<DiscoveryHandle>>>,
    server_stop: AsyncMutex<Option<oneshot::Sender<()>>>,
    discovery_stop: AsyncMutex<Option<oneshot::Sender<()>>>,
    pending_decisions:
        AsyncMutex<HashMap<String, (oneshot::Sender<PrepareUploadDecisionV2>, HashSet<String>)>>,
    send_cancellations: Mutex<HashMap<String, CancellationToken>>,
    send_sessions: Mutex<HashMap<String, SendSession>>,
}

#[derive(Clone)]
struct SendSession {
    protocol: ProtocolType,
    host: String,
    port: u16,
    session_id: String,
    fingerprint: String,
}

static JVM: OnceLock<JavaVM> = OnceLock::new();
static RUNTIME: OnceLock<Runtime> = OnceLock::new();
static ENGINE: OnceLock<Mutex<Option<Arc<Engine>>>> = OnceLock::new();

fn runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| {
        Builder::new_multi_thread()
            .enable_all()
            .thread_name("quicksend-core")
            .build()
            .expect("create Quick Send Tokio runtime")
    })
}

fn engine_slot() -> &'static Mutex<Option<Arc<Engine>>> {
    ENGINE.get_or_init(|| Mutex::new(None))
}

fn current_engine() -> Option<Arc<Engine>> {
    engine_slot().lock().ok()?.as_ref().cloned()
}

fn java_string(env: &mut JNIEnv<'_>, value: JString<'_>) -> Result<String> {
    Ok(env.get_string(&value)?.into())
}

fn java_throw(env: &mut JNIEnv<'_>, error: impl std::fmt::Display) {
    let _ = env.throw_new("java/lang/IllegalStateException", error.to_string());
}

fn callback_event(callback: &GlobalRef, event: &Value) {
    let Some(vm) = JVM.get() else { return };
    let Ok(mut env) = vm.attach_current_thread() else {
        return;
    };
    let Ok(payload) = env.new_string(event.to_string()) else {
        return;
    };
    let payload = JObject::from(payload);
    let _ = env.call_method(
        callback.as_obj(),
        "onCoreEvent",
        "(Ljava/lang/String;)V",
        &[JValue::Object(&payload)],
    );
}

fn emit(engine: &Engine, event: Value) {
    callback_event(&engine.callback, &event);
}

fn device_json(device: &DiscoveredDevice) -> Option<Value> {
    let channel = device.channel.http()?;
    Some(json!({
        "alias": device.alias,
        "fingerprint": device.fingerprint,
        "host": channel.host,
        "port": channel.port,
        "protocol": channel.protocol.as_str(),
        "deviceModel": device.device_model,
    }))
}

fn emit_device_list(engine: &Engine, discovery: &DiscoveryHandle) {
    let devices = discovery
        .devices()
        .iter()
        .filter_map(|state| device_json(&state.device))
        .collect::<Vec<_>>();
    emit(engine, json!({"type":"devices", "devices":devices}));
}

async fn start_engine(engine: Arc<Engine>) -> Result<()> {
    let (server_event_tx, mut server_event_rx) = mpsc::channel(64);
    let (server_stop_tx, server_stop_rx) = oneshot::channel();
    let server = Arc::new(
        start_with_port(
            HTTP_PORT,
            Some(TlsConfig {
                cert: engine.identity.certificate_pem.clone(),
                private_key: engine.identity.private_key_pem.clone(),
            }),
            ClientInfo {
                alias: engine.alias.clone(),
                version: PROTOCOL_VERSION_V2.to_string(),
                device_model: None,
                device_type: Some(DeviceType::Mobile),
                token: Uuid::new_v4().to_string(),
            },
            None,
            Some(ServerConfigV2 {
                pin: None,
                verify_checksums: true,
                event_tx: server_event_tx,
            }),
            WebConfig::default(),
            server_stop_rx,
        )
        .await
        .context("start LocalSend-compatible HTTPS listener")?,
    );
    *engine.server.lock().await = Some(server);
    *engine.server_stop.lock().await = Some(server_stop_tx);

    let (discovery_event_tx, mut discovery_event_rx) = mpsc::channel(64);
    let (discovery_stop_tx, discovery_stop_rx) = oneshot::channel();
    let discovery = Arc::new(
        localsend::discovery::start(
            DiscoveryConfig {
                group: DEFAULT_MULTICAST_GROUP,
                group_v6: Some(DEFAULT_MULTICAST_GROUP_V6),
                port: HTTP_PORT,
                interface_filter: InterfaceFilter::default(),
                device: MulticastDevice {
                    alias: engine.alias.clone(),
                    version: PROTOCOL_VERSION_V2.to_string(),
                    device_model: None,
                    device_type: Some(DeviceType::Mobile),
                    fingerprint: engine.identity.fingerprint.clone(),
                    port: HTTP_PORT,
                    protocol: ProtocolType::Https,
                    download: false,
                },
                identity: DiscoveryIdentity {
                    cert_pem: engine.identity.certificate_pem.clone(),
                    private_key_pem: engine.identity.private_key_pem.clone(),
                },
                timeout: Duration::from_millis(500),
                event_tx: Some(discovery_event_tx),
            },
            discovery_stop_rx,
        )
        .await,
    );
    discovery.set_answer_announcements(engine.visible.load(std::sync::atomic::Ordering::Relaxed));
    *engine.discovery.lock().await = Some(discovery.clone());
    *engine.discovery_stop.lock().await = Some(discovery_stop_tx);

    if engine.visible.load(std::sync::atomic::Ordering::Relaxed) {
        discovery.announce().await;
    }
    emit_device_list(&engine, &discovery);

    let server_engine = engine.clone();
    let server_discovery = discovery.clone();
    runtime().spawn(async move {
        while let Some(event) = server_event_rx.recv().await {
            match event {
                ServerEventV2::Register { ip, info } => {
                    if !server_engine.visible.load(std::sync::atomic::Ordering::Relaxed) {
                        continue;
                    }
                    // The LocalSend server emits this event only after matching
                    // the advertised fingerprint to the verified TLS client certificate.
                    let fingerprint = info.fingerprint.clone();
                    server_discovery.add_device(DiscoveredDevice {
                        alias: info.alias,
                        version: info.version,
                        device_model: info.device_model,
                        device_type: info.device_type,
                        fingerprint,
                        channel: localsend::discovery::DeviceChannel::Http(HttpChannel {
                            host: ip.to_string(),
                            port: info.port,
                            protocol: info.protocol,
                        }),
                        download: info.download,
                    }).await;
                    emit_device_list(&server_engine, &server_discovery);
                }
                ServerEventV2::PrepareUpload { session_id, info, cert_fingerprint, files, decision_tx, .. } => {
                    let sender = info.alias;
                    let accepted_ids = files.keys().cloned().collect::<HashSet<_>>();
                    let mut files = files.into_values().map(|file| json!({
                        "id": file.id,
                        "name": file.file_name,
                        "mimeType": file.file_type,
                        "size": file.size,
                    })).collect::<Vec<_>>();
                    files.sort_by(|a,b| a["name"].as_str().cmp(&b["name"].as_str()));
                    if let Some(fingerprint) = cert_fingerprint {
                        emit(&server_engine, json!({"type":"peerCertificate","fingerprint":fingerprint}));
                    }
                    server_engine.pending_decisions.lock().await.insert(session_id.clone(), (decision_tx, accepted_ids));
                    emit(&server_engine, json!({
                        "type":"transferRequest",
                        "transfer":{"sessionId":session_id,"sender":sender,"files":files}
                    }));
                    let timeout_engine = server_engine.clone();
                    let timeout_id = session_id.clone();
                    runtime().spawn(async move {
                        tokio::time::sleep(Duration::from_secs(90)).await;
                        if let Some((decision, _)) = timeout_engine.pending_decisions.lock().await.remove(&timeout_id) {
                            let _ = decision.send(PrepareUploadDecisionV2::Decline);
                            emit(&timeout_engine, json!({"type":"sessionEnd","sessionId":timeout_id,"reason":"expired"}));
                        }
                    });
                }
                ServerEventV2::FileUpload { session_id, file_id, file, target_tx } => {
                    match request_output_fd(&server_engine.callback, &session_id, &file_id, &file.file_name, &file.file_type) {
                        Ok(fd) if fd >= 0 => {
                            let (progress_tx, mut progress_rx) = mpsc::channel::<u64>(16);
                            let (result_tx, result_rx) = oneshot::channel();
                            let target = FileUploadTarget::Fd { fd, result_tx, progress_tx: Some(progress_tx) };
                            if let Err(target) = target_tx.send(target) {
                                if let FileUploadTarget::Fd { fd, .. } = target {
                                    unsafe { libc::close(fd); }
                                }
                                continue;
                            }
                            let outcome_engine = server_engine.clone();
                            let outcome_session = session_id.clone();
                            let outcome_file = file_id.clone();
                            runtime().spawn(async move {
                                let success = matches!(result_rx.await, Ok(Ok(())));
                                emit(&outcome_engine, json!({"type":"fileReceived","sessionId":outcome_session,"fileId":outcome_file,"success":success}));
                            });
                            let progress_engine = server_engine.clone();
                            let progress_session = session_id.clone();
                            let file_size = file.size;
                            runtime().spawn(async move {
                                while let Some(received) = progress_rx.recv().await {
                                    let progress = if file_size == 0 { 1.0 } else { (received as f64 / file_size as f64).min(1.0) };
                                    emit(&progress_engine, json!({"type":"transferProgress","sessionId":progress_session,"progress":progress,"received":received,"size":file_size}));
                                }
                            });
                        }
                        Ok(_) => {}
                        Err(error) => emit(&server_engine, json!({"type":"error","message":error.to_string()})),
                    }
                }
                ServerEventV2::SessionEnd { session_id, reason } => {
                    emit(&server_engine, json!({"type":"sessionEnd","sessionId":session_id,"reason":format!("{reason:?}")}));
                }
                ServerEventV2::PrepareUploadAborted { session_id } => {
                    server_engine.pending_decisions.lock().await.remove(&session_id);
                    emit(&server_engine, json!({"type":"sessionEnd","sessionId":session_id,"reason":"aborted"}));
                }
                ServerEventV2::CancelReceived { session_id, .. } => {
                    emit(&server_engine, json!({"type":"sessionEnd","sessionId":session_id,"reason":"cancelled"}));
                }
                ServerEventV2::ListenerFailed { error } => emit(&server_engine, json!({"type":"error","message":error})),
            }
        }
    });

    let discovery_engine = engine.clone();
    let event_discovery = discovery.clone();
    runtime().spawn(async move {
        while let Some(event) = discovery_event_rx.recv().await {
            match event {
                DiscoveryEvent::Discovered { .. } | DiscoveryEvent::Updated { .. } => emit_device_list(&discovery_engine, &event_discovery),
                DiscoveryEvent::MulticastFailed => emit(&discovery_engine, json!({"type":"error","message":"Multicast discovery is unavailable on this network."})),
            }
        }
    });
    Ok(())
}

fn request_output_fd(
    callback: &GlobalRef,
    session_id: &str,
    file_id: &str,
    name: &str,
    mime: &str,
) -> Result<i32> {
    let vm = JVM.get().ok_or_else(|| anyhow!("Java VM is unavailable"))?;
    let mut env = vm.attach_current_thread()?;
    let session = env.new_string(session_id)?;
    let file = env.new_string(file_id)?;
    let name = env.new_string(name)?;
    let mime = env.new_string(mime)?;
    let session = JObject::from(session);
    let file = JObject::from(file);
    let name = JObject::from(name);
    let mime = JObject::from(mime);
    let result = env.call_method(
        callback.as_obj(),
        "openReceivedFile",
        "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I",
        &[
            JValue::Object(&session),
            JValue::Object(&file),
            JValue::Object(&name),
            JValue::Object(&mime),
        ],
    )?;
    Ok(result.i()?)
}

#[derive(Deserialize)]
struct TargetDevice {
    alias: String,
    fingerprint: String,
    host: String,
    port: u16,
    protocol: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SharedFile {
    id: String,
    name: String,
    mime_type: String,
    size: u64,
}

fn parse_protocol(protocol: &str) -> Result<ProtocolType> {
    match protocol.to_ascii_lowercase().as_str() {
        "http" => Ok(ProtocolType::Http),
        "https" => Ok(ProtocolType::Https),
        _ => Err(anyhow!("Unsupported LocalSend protocol: {protocol}")),
    }
}

fn start_send(
    engine: Arc<Engine>,
    transfer_id: String,
    device_json: String,
    files_json: String,
    owned_descriptors: Vec<OwnedFd>,
) -> Result<()> {
    let owned_descriptors = owned_descriptors;
    let device: TargetDevice = serde_json::from_str(&device_json)?;
    let files: Vec<SharedFile> = serde_json::from_str(&files_json)?;
    if files.len() != owned_descriptors.len() || files.is_empty() {
        return Err(anyhow!("The selected files could not be read"));
    }
    let identity = engine.identity.clone();
    let token = CancellationToken::new();
    engine
        .send_cancellations
        .lock()
        .map_err(|_| anyhow!("Transfer state is unavailable"))?
        .insert(transfer_id.clone(), token.clone());
    runtime().spawn(async move {
        let result = async {
            let protocol = parse_protocol(&device.protocol)?;
            let expected_fingerprint = if protocol == ProtocolType::Https { Some(device.fingerprint.clone()) } else { None };
            let client = LsHttpClientV2::try_new(
                &identity.private_key_pem,
                &identity.certificate_pem,
                expected_fingerprint,
                None,
            )?;
            let files_dto = files.iter().map(|file| FileDto {
                id: file.id.clone(),
                file_name: file.name.clone(),
                size: file.size,
                file_type: file.mime_type.clone(),
                sha256: None,
                preview: None,
                metadata: None,
            }).map(|file| (file.id.clone(), file)).collect();
            let request = PrepareUploadRequestDtoV2 {
                info: RegisterDtoV2 {
                    alias: engine.alias.clone(),
                    version: PROTOCOL_VERSION_V2.to_string(),
                    device_model: None,
                    device_type: Some(DeviceType::Mobile),
                    fingerprint: identity.fingerprint.clone(),
                    port: HTTP_PORT,
                    protocol: ProtocolType::Https,
                    download: false,
                },
                files: files_dto,
            };
            emit(&engine, json!({"type":"sendStarted","transferId":transfer_id,"target":device.alias}));
            let prepared = client.prepare_upload(protocol, &device.host, device.port, None, request, None, token.clone()).await?;
            let response = prepared.response.ok_or_else(|| anyhow!("The receiver did not accept any files"))?;
            engine.send_sessions.lock().map_err(|_| anyhow!("Transfer state is unavailable"))?.insert(transfer_id.clone(), SendSession {
                protocol,
                host: device.host.clone(),
                port: device.port,
                session_id: response.session_id.clone(),
                fingerprint: device.fingerprint.clone(),
            });
            for (file, descriptor) in files.iter().zip(owned_descriptors.into_iter()) {
                let Some(file_token) = response.files.get(&file.id) else { continue };
                // The LocalSend core takes ownership of this descriptor once its stream is created.
                let fd = descriptor.into_raw_fd();
                let content = FileContent::Fd(fd);
                let mut sent = 0u64;
                let mut last_emit = Instant::now();
                let callback_engine = engine.clone();
                let progress_id = transfer_id.clone();
                let progress_file = file.id.clone();
                let size = file.size;
                let stream = content.into_stream().inspect(move |chunk| {
                    if let Ok(bytes) = chunk {
                        sent = sent.saturating_add(bytes.len() as u64);
                        if sent >= size || last_emit.elapsed() >= Duration::from_millis(250) {
                            last_emit = Instant::now();
                            let progress = if size == 0 { 1.0 } else { (sent as f64 / size as f64).min(1.0) };
                            emit(&callback_engine, json!({"type":"sendProgress","transferId":progress_id,"fileId":progress_file,"progress":progress}));
                        }
                    }
                });
                let body = localsend::reqwest::Body::wrap_stream(stream);
                if let Err(error) = client.upload(protocol, &device.host, device.port, None, &response.session_id, &file.id, file_token, body, token.clone()).await {
                    let _ = client.cancel(protocol, &device.host, device.port, &response.session_id).await;
                    return Err(error.into());
                }
                emit(&engine, json!({"type":"sendProgress","transferId":transfer_id,"fileId":file.id,"progress":1.0}));
            }
            Ok::<(), anyhow::Error>(())
        }.await;

        if let Err(error) = result {
            emit(&engine, json!({"type":"sendFailed","transferId":transfer_id,"message":error.to_string()}));
        } else {
            emit(&engine, json!({"type":"sendComplete","transferId":transfer_id}));
        }
        if let Ok(mut cancellations) = engine.send_cancellations.lock() {
            cancellations.remove(&transfer_id);
        }
        if let Ok(mut sessions) = engine.send_sessions.lock() {
            sessions.remove(&transfer_id);
        }
    });
    Ok(())
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_ensignsoft_quicksend_core_NativeQuickSend_generateIdentity(
    mut env: JNIEnv<'_>,
    _class: JClass<'_>,
) -> jstring {
    match generate_self_signed().and_then(|identity| {
        serde_json::to_string(&Identity::from(identity)).map_err(anyhow::Error::from)
    }) {
        Ok(value) => env
            .new_string(value)
            .map(JString::into_raw)
            .unwrap_or(std::ptr::null_mut()),
        Err(error) => {
            java_throw(&mut env, error);
            std::ptr::null_mut()
        }
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_ensignsoft_quicksend_core_NativeQuickSend_initialize(
    mut env: JNIEnv<'_>,
    _class: JClass<'_>,
    callback: JObject<'_>,
    alias: JString<'_>,
    identity_json: JString<'_>,
    visible: jboolean,
) {
    let setup = (|| -> Result<()> {
        let vm = env.get_java_vm()?;
        let _ = JVM.set(vm);
        let callback = env.new_global_ref(callback)?;
        let alias = java_string(&mut env, alias)?;
        let identity: Identity = serde_json::from_str(&java_string(&mut env, identity_json)?)?;
        let mut slot = engine_slot()
            .lock()
            .map_err(|_| anyhow!("Core state is unavailable"))?;
        if slot.is_some() {
            return Ok(());
        }
        let engine = Arc::new(Engine {
            callback,
            identity,
            alias,
            visible: std::sync::atomic::AtomicBool::new(visible != 0),
            server: AsyncMutex::new(None),
            discovery: AsyncMutex::new(None),
            server_stop: AsyncMutex::new(None),
            discovery_stop: AsyncMutex::new(None),
            pending_decisions: AsyncMutex::new(HashMap::new()),
            send_cancellations: Mutex::new(HashMap::new()),
            send_sessions: Mutex::new(HashMap::new()),
        });
        *slot = Some(engine.clone());
        drop(slot);
        runtime().spawn(async move {
            if let Err(error) = start_engine(engine.clone()).await {
                emit(&engine, json!({"type":"error","message":error.to_string()}));
                if let Ok(mut slot) = engine_slot().lock() {
                    *slot = None;
                }
            }
        });
        Ok(())
    })();
    if let Err(error) = setup {
        java_throw(&mut env, error);
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_ensignsoft_quicksend_core_NativeQuickSend_respond(
    mut env: JNIEnv<'_>,
    _class: JClass<'_>,
    session_id: JString<'_>,
    accepted: jboolean,
) {
    let result = (|| -> Result<()> {
        let session_id = java_string(&mut env, session_id)?;
        let engine = current_engine().ok_or_else(|| anyhow!("Receiver is not running"))?;
        runtime().spawn(async move {
            if let Some((decision_tx, accepted_ids)) = engine.pending_decisions.lock().await.remove(&session_id) {
                let decision = if accepted != 0 {
                    PrepareUploadDecisionV2::Accept(accepted_ids)
                } else {
                    PrepareUploadDecisionV2::Decline
                };
                    let _ = decision_tx.send(decision);
                    emit(&engine, json!({"type":"transferDecision","sessionId":session_id,"accepted":accepted != 0}));
            }
        });
        Ok(())
    })();
    if let Err(error) = result {
        java_throw(&mut env, error);
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_ensignsoft_quicksend_core_NativeQuickSend_setVisibility(
    mut env: JNIEnv<'_>,
    _class: JClass<'_>,
    visible: jboolean,
) {
    if let Some(engine) = current_engine() {
        let is_visible = visible != 0;
        engine
            .visible
            .store(is_visible, std::sync::atomic::Ordering::Relaxed);
        runtime().spawn(async move {
            if let Some(discovery) = engine.discovery.lock().await.as_ref() {
                discovery.set_answer_announcements(is_visible);
                if is_visible {
                    discovery.announce().await;
                }
            }
        });
    } else {
        java_throw(&mut env, "Network core has not started");
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_ensignsoft_quicksend_core_NativeQuickSend_send(
    mut env: JNIEnv<'_>,
    _class: JClass<'_>,
    device_json: JString<'_>,
    files_json: JString<'_>,
    descriptors: JIntArray<'_>,
    transfer_id: JString<'_>,
) {
    let result = (|| -> Result<()> {
        let device_json = java_string(&mut env, device_json)?;
        let files_json = java_string(&mut env, files_json)?;
        let transfer_id = java_string(&mut env, transfer_id)?;
        let length = env.get_array_length(&descriptors)?;
        let mut values = vec![0; length as usize];
        env.get_int_array_region(&descriptors, 0, &mut values)?;
        let owned_descriptors = values
            .into_iter()
            .map(|fd| unsafe { OwnedFd::from_raw_fd(fd) })
            .collect();
        let engine = current_engine().ok_or_else(|| anyhow!("Network core has not started"))?;
        start_send(
            engine,
            transfer_id,
            device_json,
            files_json,
            owned_descriptors,
        )?;
        Ok(())
    })();
    if let Err(error) = result {
        java_throw(&mut env, error);
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_ensignsoft_quicksend_core_NativeQuickSend_cancel(
    mut env: JNIEnv<'_>,
    _class: JClass<'_>,
    transfer_id: JString<'_>,
) {
    let result = (|| -> Result<()> {
        let transfer_id = java_string(&mut env, transfer_id)?;
        let engine = current_engine().ok_or_else(|| anyhow!("Network core has not started"))?;
        let token = engine
            .send_cancellations
            .lock()
            .ok()
            .and_then(|items| items.get(&transfer_id).cloned());
        let send_session = engine
            .send_sessions
            .lock()
            .ok()
            .and_then(|mut items| items.remove(&transfer_id));
        runtime().spawn(async move {
            if let Some(token) = token {
                token.cancel();
            }
            if let Some(session) = send_session {
                if let Ok(client) = LsHttpClientV2::try_new(
                    &engine.identity.private_key_pem,
                    &engine.identity.certificate_pem,
                    if session.protocol == ProtocolType::Https {
                        Some(session.fingerprint)
                    } else {
                        None
                    },
                    None,
                ) {
                    let _ = client
                        .cancel(
                            session.protocol,
                            &session.host,
                            session.port,
                            &session.session_id,
                        )
                        .await;
                }
            } else if let Some(server) = engine.server.lock().await.as_ref() {
                if server.cancel_v2_session(&transfer_id).await {
                    emit(
                        &engine,
                        json!({"type":"sessionEnd","sessionId":transfer_id,"reason":"cancelled"}),
                    );
                }
            }
        });
        Ok(())
    })();
    if let Err(error) = result {
        java_throw(&mut env, error);
    }
}

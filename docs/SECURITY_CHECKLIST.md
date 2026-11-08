# Security checklist / Güvenlik kontrol listesi

Status reviewed on 2026-11-08 for Quick Send 0.1.0.

## Permissions

| Platform | Permission | Why | Status |
|---|---|---|---|
| Android | INTERNET, ACCESS_WIFI_STATE, CHANGE_WIFI_MULTICAST_STATE | LAN HTTPS + multicast discovery | required |
| Android | ACCESS_LOCAL_NETWORK | Android 17+ local network access | required |
| Android | POST_NOTIFICATIONS | progress / accept-decline notifications (runtime-requested on 13+) | required |
| Android | FOREGROUND_SERVICE(_CONNECTED_DEVICE) | background receive | required |
| Android | SYSTEM_ALERT_WINDOW | added by RN debug tooling | **removed** via `tools:node="remove"` ✅ |
| Linux | none beyond user session; TCP/UDP 53317 via opt-in firewalld service | | ✅ |

- [x] No storage permission: received files are written through MediaStore to `Downloads/Quick Send`.
- [x] Exported components: launcher/share activity (needed) and QS tile (protected by `BIND_QUICK_SETTINGS_TILE`); service and receiver are not exported.

## Transport and certificates

- [x] TLS identity generated locally; Android private key encrypted with an Android Keystore key.
- [x] Peer certificate fingerprint is checked in Rust core (`packages/core`, covered by `tests/v2_tls_pinning.rs`); JNI bridge forwards the verified cert fingerprint and does not bypass it.
- [x] Receiver approval: every incoming session requires an explicit accept (UI or notification action) unless the user changes upstream auto-accept settings on Linux.
- [ ] Re-verify after every upstream sync (see UPSTREAM_SYNC.md).

## Untrusted input

- [x] File names from peers are sanitized before saving (Android: `QuickSendFiles.safeName` strips `/`, `\`, control chars, leading/trailing dots, length ≤240; unit-tested). Linux uses upstream sanitizing in `packages/localsend_isolates/lib/src/task/server/file_saver.dart` (refuses `..` and absolute names, `p.isWithin` check).
- [x] Received files are finalized only after core reports a successful checksum/size verification.
- [x] Device alias / text messages are rendered as plain text (no HTML/markup evaluation).
- [x] Update check accepts only `https://github.com/<repo>/…` release URLs from the API response; anything else falls back to the fixed releases page.

## Network surface

- [x] No new endpoints, analytics, telemetry or third-party services. The only extra request is the user-triggered GitHub Releases API call.
- [x] Ports: TCP+UDP 53317 (inherited LocalSend protocol), multicast 224.0.0.167.

## Secrets and supply chain

- [x] No keystore, passwords or tokens in the repository; signing via GitHub Secrets only (`docs/RELEASE.md`).
- [x] Release job deletes the decoded keystore after use; release job has the only `contents: write` permission.
- [x] No GPL code added.
- [ ] Pin third-party GitHub Actions to commit SHAs before the first public release.

# Manual test checklist / Manuel test listesi

Record device models, OS versions, build/commit and result (✅/❌ + note) for
each run. Devices: A = Android (Quick Send), B = Android (Quick Send),
L = Fedora (RPM), I = AppImage, S = upstream LocalSend client.

## Automated coverage

| Area | Where | Command |
|---|---|---|
| Full upload flow, accept/reject, SHA-256, retry | `packages/core/tests/v2_server.rs` (upstream) | `cargo test -p localsend --features full` |
| Two endpoints over TLS with certificate pinning | `packages/core/tests/v2_tls_pinning.rs` (upstream) | same |
| Received file-name sanitizing (path traversal) | `mobile/android/app/src/test/.../QuickSendFilesTest.kt` | `cd mobile/android && ./gradlew testDebugUnitTest` |
| Update-check logic | `app/test/unit/quick_send/`, `mobile/__tests__/updateCheck.test.ts` | `fvm flutter test`, `npm test` |
| Linux responsive layout | `app/test/widget/responsive_builder_test.dart` | `fvm flutter test` |

## Installation

- [ ] L: `sudo dnf install ./quicksend-*.rpm` succeeds on current Fedora; app appears in GNOME with icon.
- [ ] L: `sudo firewall-cmd --permanent --add-service=quicksend && sudo firewall-cmd --reload`; devices discover each other.
- [ ] L: without the firewalld service, discovery from other devices fails (documents the expected problem).
- [ ] L: `sudo dnf remove quicksend` removes files; `/usr/lib/firewalld/services/quicksend.xml` gone.
- [ ] I: AppImage starts on Fedora and Ubuntu 22.04; tray icon visible.
- [ ] A: signed release APK installs; upgrade over previous release keeps settings.

## Transfers (run A↔B, A↔L, L↔I, A↔S, L↔S)

- [ ] Single small file.
- [ ] Multiple files (≥20, mixed types) in one transfer.
- [ ] Large file (≥4 GB) — completes, checksum/size match on receiver.
- [ ] File names with Turkish characters, spaces, emoji.
- [ ] Receiver **declines** → sender shows declined, nothing saved.
- [ ] Sender **cancels** mid-transfer → receiver cleans up partial file.
- [ ] Receiver cancels mid-transfer.
- [ ] **Network drop** (Wi-Fi off) mid-transfer → both sides show an error, no crash, no half file presented as complete.
- [ ] Network with **client isolation** (guest Wi-Fi / AP isolation): devices are not found; app shows the "no devices / same Wi-Fi" hint and the troubleshooting text, no crash.
- [ ] Device visibility **Off** → device not discoverable, incoming requests not shown.

## Android specifics

- [ ] Share sheet: ACTION_SEND from Gallery and ACTION_SEND_MULTIPLE from Files open Quick Send with files pre-selected.
- [ ] Quick Settings tile toggles receiving; state matches in app.
- [ ] Android 13+: first start asks notification permission; denying still allows foreground use.
- [ ] Background receive: app in background / screen off, foreground notification visible, accept/decline from notification works, progress shown.
- [ ] TalkBack: every button and device card is announced; touch targets ≥48dp; light/dark/dynamic colour readable.

## Linux specifics

- [ ] Close window with "minimize to tray" → keeps receiving; tray menu restores/quits.
- [ ] GNOME Wayland: file picker is the portal dialog (`xdg-desktop-portal-gnome`); KDE: portal KDE dialog.
- [ ] Window resize from narrow to wide switches mobile ↔ desktop layout correctly.

## Protocol compatibility

- [ ] Upstream LocalSend (latest) → Quick Send and back, on Android and Linux.
- [ ] Fingerprint shown/verified; changing a peer certificate is not silently accepted.

# Quick Send change notes

This file records downstream changes for files that cannot carry source comments
(such as JSON localization and packaging metadata) and gives reviewers a quick
map of the fork-specific surface.

## Phase 1 identity

- `app/assets/i18n/*.json`: visible product-name strings now say Quick Send;
  English and Turkish About copy includes the LocalSend attribution and the
  current Android/Linux platform scope.
- `app/assets/img/*`, Android launcher resources, and
  `support/build/appimage/quick-send.png`: placeholder Quick Send paper-plane
  mark; these are temporary identity assets.
- `app/lib/pages/about/about_page.dart`, `app/lib/widget/quick_send_logo.dart`,
  settings and home/error pages: Quick Send presentation; About preserves
  upstream contributors and links as attribution.
- `app/android/app/build.gradle` and Android manifest: Android application ID
  and visible labels use Quick Send. Existing Kotlin namespace remains an
  internal implementation detail.
- `app/linux/CMakeLists.txt`, `app/linux/my_application.cc`, and AppImage
  desktop recipes: Linux binary/application identity uses Quick Send.
- `README.md`, `NOTICE`, and `docs/UPSTREAM_SYNC.md`: downstream project
  description, attribution, and merge procedure.

No protocol model, route, port, TLS certificate, fingerprint verification, or
receiver approval logic was changed in Phase 1.

## Phase 2 Android interface

- `mobile/` is the Android-only React Native 0.88 application. Material 3
  components use system dynamic colors when available, with light/dark/system
  appearance, English/Turkish strings, device discovery/list, transfer
  approval, progress, and visibility controls.
- `mobile/android/` contains the Android package identity, platform permission
  requests, share intents, file selection and URI handling, notification
  actions, Quick Settings tile, and the `connectedDevice` foreground receive
  service for the local-network connection.
- `mobile/rust/` is an isolated JNI crate that calls the existing
  `packages/core`; protocol routes, payloads, TLS trust checks, and receive
  approval stay in Rust core.
- Android private TLS identity material is encrypted with an Android Keystore
  key. Received files are finalized in Downloads/Quick Send after the core
  reports successful checksum verification.

Do not add LocalSend network behavior to JavaScript or Kotlin. Preserve the
Android permission and receiver approval flow when changing this bridge.

## Phase 3 Linux desktop

- Flutter keeps the Material 3 navigation rail and responsive content widths;
  responsive breakpoints now use the actual available layout constraints.
- Linux default window sizing follows the desktop layout, and the default
  Material seed color matches Quick Send's Android fallback color.
- Existing tray and close-to-tray behavior use Quick Send's icon identity.
- `app/linux/packaging/` contains the system desktop entry, hicolor icon sizes,
  tray icon, and AppStream metadata. AppImage recipes install the same metadata.
- The existing `file_selector_linux` implementation creates a GTK
  `GtkFileChooserNative`; GTK uses the FileChooser portal when it is available
  on the user's session bus, which covers GNOME/Wayland portal installations.

## Phase 4 packaging

- `packaging/rpm/quicksend.spec` + `build-rpm.sh`: binary RPM from the Flutter
  release bundle, installed under `/opt/quicksend`; build-tree RUNPATHs are
  rewritten to `$ORIGIN`. Requires GTK 3, xdg-desktop-portal and a GTK/GNOME/KDE
  portal backend.
- `packaging/firewalld/quicksend.xml`: TCP+UDP 53317 (from
  `packages/localsend_isolates/lib/constants.dart`). Not enabled automatically.
- `app/pubspec.yaml`: Quick Send's own version line (0.1.0) replaces upstream's.

## Phase 5 CI/CD and update check

- `.github/workflows/`: upstream Windows/macOS/WinGet/deb/tar/CLI and
  Flutter-Android workflows removed. `ci.yml` checks that Quick Send versions match and
  adds React Native and JNI-crate jobs. `release.yml` builds a signed Android
  APK/AAB, the AppImage and the RPM, then publishes a GitHub Release on `v*` tags.
- `mobile/android/app/build.gradle`: release signing only from `QS_*`
  environment variables; `RELEASES_REPO` BuildConfig field.
- `app/lib/quick_send/` and `mobile/src/updateCheck.ts`: user-triggered
  GitHub Releases check (one request per button press, no background calls).

## Phase 6 tests and checklists

- `docs/TEST_CHECKLIST.md`, `docs/SECURITY_CHECKLIST.md`; unit tests for
  file-name sanitizing (Kotlin) and update-check logic (Dart, TypeScript).

## Android build note

The Flutter `app/android` project is inherited from upstream but **is not built
or released**. The released Android app is `mobile/` (React Native + JNI to
`packages/core`). Both share the same application ID, so never publish
`app/android` output.

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

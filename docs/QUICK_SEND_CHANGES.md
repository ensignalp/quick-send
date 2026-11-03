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

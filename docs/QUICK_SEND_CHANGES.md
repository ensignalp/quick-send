# Quick Send change notes

This file records downstream changes for files that cannot carry source comments
(such as JSON localization and packaging metadata) and gives reviewers a quick
map of the fork-specific surface.

## Phase 1 identity

- `app/assets/i18n/*.json`: visible product-name strings now say Quick Send;
  English and Turkish About copy includes the LocalSend attribution and the
  current Android/Linux platform scope.
- `app/assets/img/*`, Android launcher resources, and
  `support/build/appimage/quick-send.png`: Quick Send brand icon. The sources
  are `support/brand/quick-send-mark.svg` (the mark) and
  `support/brand/quick-send-icon.svg` (app icon); run
  `support/brand/generate.sh` to regenerate every raster icon. The Android
  launcher is an adaptive vector icon with a themed (monochrome) layer.
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

## Expo tooling (mobile)

- `mobile/` uses Expo SDK 58 (matches RN 0.88) in the bare workflow via
  `install-expo-modules`: Expo CLI, dev client, web and Expo Go preview.
- `react-native-vector-icons` replaced by `@expo/vector-icons` (same icon set).
- `src/previewBridge.ts` simulates the native bridge in development when the
  native module is absent (Expo Go/web). It is never used in release builds and does no networking.

## UI simplification (design language, icons, fonts)

- Desktop home (`app/lib/quick_send/share_home.dart`): wide windows use a
  LocalSend-style navigation rail (Receive / Send / Settings) in the Android
  app's colours; narrow windows use the phone layout. The tab is the upstream
  `homePageControllerProvider` tab, so drag & drop, command-line files, the tray
  and keyboard shortcuts switch tabs.
- The tray "Quick panel" entry and compact window were removed, as were the
  "All settings" entry and the upstream `SettingsTab` it opened (plus the files
  only that screen used: `changelog_page.dart`, `encryption_disabled_notice.dart`,
  `quick_save_notice.dart`, `quick_save_from_favorites_notice.dart`,
  `text_field_with_actions.dart`).
- Title bar: `WindowBrightnessWatcher` (upstream #3480) is removed, so GTK draws
  the system-default title bar instead of having its theme switched at runtime.
- Several local IPs are offered in a dropdown (desktop info dialog, web share
  page, manual-address network; Android info sheet). In the manual-address
  dialog a number tried on several networks never picks a device
  automatically; the user chooses from the devices that answered.
- Space Grotesk is the only app typeface (`qsFontFamily`, including the Yaru
  theme and the init-error screen); platform fonts are glyph fallbacks only.
- Icons: hicolor 16–512 px + SVG, window icon, AppImage desktop integration in
  `AppRun` (desktop file, icons, GNOME Files custom icon), file-manager menu
  icon name, Android launcher via `mipmap` adaptive icons, store listing icon.

## Desktop: phone layout, GNOME window, single instance

- The navigation rail is gone: every window size uses the phone layout (device
  name pill on top, 3-dot menu with Settings on the right, Receive/Send toggle at
  the bottom). Settings opens as a page with a back arrow. Default window size
  900×500 (`my_application.cc`, `window_dimensions_provider.dart`); the saved
  size moved to new keys (`qs_window_width`/`qs_window_height`) so older saved
  sizes do not override it.
- GNOME title bar (`app/linux/my_application.cc`): on GNOME the window has a
  GtkHeaderBar with libadwaita-style window controls, the Adwaita GTK theme and
  the system `color-scheme` (light/dark, updated live) and `button-layout`.
  Root cause of "window buttons only visible on hover": GTK3 apps load
  `~/.config/gtk-3.0/gtk.css`; theming tools write title button rules there
  (e.g. colours from an undefined `@window-fg-color`, icons set to
  `color: transparent`) that hide the icons until hover. GNOME's own apps are
  GTK4/libadwaita and never read that file. The app's provider sits above the
  user stylesheet (`GTK_STYLE_PROVIDER_PRIORITY_USER + 100`).
- File manager menu: the Nautilus *script* (`Scripts > Quick Send`) is no longer
  installed and is removed on start; "Send with Quick Send" (nautilus-python)
  and the KDE service menu remain.
- Single instance on Linux (`lib/quick_send/single_instance.dart`): a per-user
  Unix socket in `$XDG_RUNTIME_DIR`. The upstream HTTP `show` handover only
  works while the receive server runs, and Quick Send stops it while sharing is
  off, so a second launch used to start a second app in that mode.
- Removed: LocalSend's "What's new" page, the unused upstream `ReceiveTab` and
  `SendTab` widgets (`pickerOptions` moved to `send_tab_vm.dart`), the LocalSend
  store screenshots in `fastlane/`, the `yaru` dependency (theme option, Yaru
  window plugin and its bundled Ubuntu fonts; a saved "yaru" colour mode falls
  back to the default).
- Desktop sessions are matched to device tiles by fingerprint, not IP.
- Icons: Linux icons (`support/brand/quick-send-icon-desktop.svg`) keep an 8%
  margin like other launcher icons; the tray mark is 28 px on the 32 px canvas.
  `AppRun` bumps the icon theme directory's mtime when it updates icons so GNOME
  Shell (dock, app grid) reloads them instead of showing a cached copy.

## 1.0.0

- After a successful send the app confirms "Sent to …", clears the selection
  and returns to the Receive screen (Android `App.tsx`; desktop `share_home.dart`
  via `quick_send/transfer_events.dart`, because the upstream send provider
  removes successful background sessions silently). A send with a failed file
  stays on screen for retry. Desktop transfer pages of sends close themselves.
- Desktop screens in the app's design language: incoming request
  (`receive_page.dart`), transfer/finished page with a "Received"/"Sent" header
  (`progress_page.dart`), language (`language_page.dart`), network interfaces
  (`settings/network_interfaces_page.dart`) and the device context menu.
  Shared pieces: `QsPage`, `qsMenuItem`, `qsMenuShape` in `qs_style.dart`.
- Title bar follows the app's light/dark theme (`title_bar_sync.dart` →
  `setTitleBarDark` in `my_application.cc`); the desktop colour scheme only
  until the app reports its theme.
- Trusted devices are accepted without a prompt also while the UI is not
  running: Android decides in the receiver service (`QuickSendTrust`,
  `QuickSendCoreHost`) from the settings the UI stores, restarts the service
  after reboot/update (`QuickSendBootReceiver`), offers the battery
  optimisation exemption (Settings → Receive in the background) and posts a
  "Received" notification. Linux (tray, window hidden) posts a desktop
  notification (`desktop_notify.dart`). Untrusted devices are unchanged.
- Signed background updates from GitHub Releases (`auto_update.dart`,
  `QuickSendUpdater.kt`, `support/scripts/update-signing.sh`, release workflow);
  see docs/RELEASE.md §3.
- Version 1.0.0 (pubspec, Android versionName/versionCode 2, AppImage recipes,
  RPM).

## Over the internet (iroh) and release setup

- New: transfers between different networks (`packages/qs_internet`, iroh 1.4 +
  iroh-blobs 0.104). The sender shares the files as an iroh-blobs collection and
  gets a code (a `BlobTicket`, sendme-compatible); the receiver dials the sender
  by its endpoint id: direct QUIC with hole punching, otherwise an encrypted iroh
  relay (n0's public relays by default; an own relay can be compiled in with
  `QS_IROH_RELAY=https://…`). BLAKE3-verified, resumable (retrying the same code
  continues). Received file names are sanitised, existing files are never
  overwritten. The local-network path is unchanged.
  - Android: JNI functions in `mobile/rust/src/android.rs`, `QuickSendInternet.kt`
    (copies picked files into the cache, publishes received files to
    Downloads/Quick Send), `InternetSheet` in `App.tsx` (menu › Over the internet;
    the code is passed on with the system share sheet).
  - Desktop: the `qs-internet` helper binary (same crate) is bundled next to the
    executable by `support/build/linux/bundle-internet-helper.sh`;
    `quick_send/internet_transfer.dart` + `internet_page.dart` (menu › Over the
    internet, code as text and QR code).
- Autostart on Linux is offered once on first start; the autostart entry now
  points at the AppImage file instead of its temporary mount (and is repaired on
  start if it points elsewhere).
- Privacy notice mentions the internet transfer relay and update checks.
- Android versionCode is derived from versionName (X·10000 + Y·100 + Z) locally
  and in CI. Windows installer and CLI versions follow the app (1.0.0).
- Releases: repository `ensignalp/quick-send`; signing material lives outside the
  repository (see docs/RELEASE.md).

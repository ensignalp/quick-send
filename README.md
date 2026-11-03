# Quick Send

Quick Send, internet bağlantısı olmadan aynı yerel ağdaki cihazlar arasında dosya ve mesaj aktarmak için geliştirilmiş açık kaynaklı bir uygulamadır. Android ve Linux'u hedefler; ağ keşfi, HTTPS aktarımı, otomatik TLS sertifikası ve alıcı onayı LocalSend protokol çekirdeğini kullanır.

Quick Send, LocalSend tabanlıdır. Yerel ağ protokol uygulaması Apache License 2.0 kapsamındadır; upstream telif bildirimleri korunur. Ayrıntılar için [NOTICE](NOTICE) ve [UPSTREAM_SYNC.md](docs/UPSTREAM_SYNC.md) dosyalarına bakın.

Geliştirici: Muhammed Alparslan Sancaktar · Ensignsoft.

> Android arayüzü React Native'e taşınma aşamasındadır. Bu Phase 1 anlık görüntüsünde Android derlemesi henüz upstream Flutter uygulamasını kullanır; React Native derleme adımları Phase 2 tamamlanınca bu README'ye eklenecektir.

## Linux'ta derleme

Gereksinimler: FVM, Flutter 3.41.9, Rust 1.97.1 ve GTK 3 geliştirme paketleri.

```sh
cd app
fvm flutter pub get
fvm dart run slang
fvm flutter analyze
fvm flutter test
fvm flutter build linux --release
```

Çıktı `app/build/linux/x64/release/bundle/` altında oluşur.

## Android geçiş dönemi derlemesi

Android için JDK 21 ve Android SDK gerekir. Bu geçiş aşamasında:

```sh
cd app
fvm flutter pub get
fvm flutter build apk --release
```

Android application ID: `com.ensignsoft.quicksend`.

## Geliştirme ortamı sürümleri

- Flutter: [.fvmrc](.fvmrc) içindeki sürüm (3.41.9)
- Rust: [rust-toolchain.toml](rust-toolchain.toml) içindeki sürüm (1.97.1)

Ağ uç noktaları, telemetri veya üçüncü taraf servis eklenmemiştir. Protokol uyumluluğu ve sertifika doğrulaması hakkında güncel değişiklik sınırları [docs/UPSTREAM_SYNC.md](docs/UPSTREAM_SYNC.md) içinde açıklanır.

---

# Quick Send

Quick Send is an open-source application for transferring files and messages between devices on the same local network without an internet connection. It targets Android and Linux. Network discovery, HTTPS transfer, automatically generated TLS certificates, and receiver approval use the LocalSend protocol core.

Quick Send is based on LocalSend. Its local-network protocol implementation is distributed under the Apache License 2.0, and upstream copyright notices are retained. See [NOTICE](NOTICE) and [UPSTREAM_SYNC.md](docs/UPSTREAM_SYNC.md) for details.

Developer: Muhammed Alparslan Sancaktar · Ensignsoft.

> The Android interface is being migrated to React Native. In this Phase 1 snapshot, Android builds still use the upstream Flutter application; React Native build instructions will be added here after Phase 2.

## Build on Linux

Requirements: FVM, Flutter 3.41.9, Rust 1.97.1, and GTK 3 development packages.

```sh
cd app
fvm flutter pub get
fvm dart run slang
fvm flutter analyze
fvm flutter test
fvm flutter build linux --release
```

The bundle is created under `app/build/linux/x64/release/bundle/`.

## Android transition build

Android builds require JDK 21 and the Android SDK. During the transition:

```sh
cd app
fvm flutter pub get
fvm flutter build apk --release
```

Android application ID: `com.ensignsoft.quicksend`.

## Development toolchain

- Flutter: version pinned in [.fvmrc](.fvmrc) (3.41.9)
- Rust: version pinned in [rust-toolchain.toml](rust-toolchain.toml) (1.97.1)

No network endpoints, analytics, telemetry, or third-party services have been added. See [docs/UPSTREAM_SYNC.md](docs/UPSTREAM_SYNC.md) for protocol compatibility and the change boundaries used when syncing upstream.

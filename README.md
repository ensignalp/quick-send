# Quick Send

Quick Send, aynı yerel ağdaki cihazlar arasında dosya ve mesaj aktarır. Android uygulaması React Native arayüzü ve LocalSend protokol çekirdeğine bağlanan bir JNI köprüsü kullanır. Linux uygulaması, Quick Send kimliğine uyarlanmış Flutter arayüzünü kullanmaya devam eder. Yerel ağ keşfi, HTTPS aktarımı, otomatik TLS kimliği, sertifika parmak izi doğrulaması ve alıcı onayı LocalSend Rust çekirdeğinde kalır.

Quick Send, [LocalSend](https://github.com/localsend/localsend) tabanlıdır. Apache-2.0 lisansı ve upstream telif bildirimleri korunmuştur; ayrıntılar için [NOTICE](NOTICE) ve [LICENSE](LICENSE) dosyalarına bakın. Uygulamanın Hakkında ekranında da LocalSend atfı bulunur.

Geliştirici: Muhammed Alparslan Sancaktar · Ensignsoft.

## Android

Gereksinimler: Node.js 22.11 veya üzeri, JDK 21, Android SDK Platform 37, Android NDK 27.1.12297006 ve `mobile/rust/rust-toolchain.toml` dosyasında sabitlenen Rust araç zinciri. Minimum Android sürümü Android 10 (API 29).

```sh
cd mobile
npm ci
npm run typecheck
npm test -- --runInBand
npm run lint
npm run android -- --mode debug
```

Bağlı bir cihaz olmadan APK üretmek için:

```sh
cd mobile/android
./gradlew assembleDebug
```

APK `mobile/android/app/build/outputs/apk/debug/app-debug.apk` konumunda oluşur. Android application ID: `com.ensignsoft.quicksend`. Android 13 ve üzeri, arka plan alımını başlatmadan önce bildirim izni ister. Android 17 ve üzeri, cihaz keşfi için yerel ağ izni ister.

## Linux

Gereksinimler: FVM, Flutter 3.41.9, Rust 1.97.1 ve GTK 3 geliştirme paketleri.

```sh
cd app
fvm flutter pub get
fvm dart run slang
fvm flutter analyze
fvm flutter test
fvm flutter build linux --release
```

Uygulama paketi `app/build/linux/x64/release/bundle/` altında oluşur. Linux uygulama kimliği: `com.ensignsoft.quicksend`.

## Geliştirme araç zincirleri

- Flutter: Linux için [.fvmrc](.fvmrc) içinde 3.41.9 sürümüne sabitlenmiştir.
- Rust: Linux için [rust-toolchain.toml](rust-toolchain.toml) içinde 1.97.1 sürümüne sabitlenmiştir; Android JNI kasası da `mobile/rust/` altında bu sürüme sabitlenmiştir.
- React Native: 0.88; bağımlılıklar `mobile/package-lock.json` ile sabitlenir.

Quick Send analitik, telemetri veya üçüncü taraf servis eklemez. Upstream güncelleme sınırları ve protokol uyumluluğu [docs/UPSTREAM_SYNC.md](docs/UPSTREAM_SYNC.md) içinde açıklanır.

---

# Quick Send

Quick Send transfers files and messages between devices on the same local network. Android uses a React Native interface and a JNI bridge to the LocalSend protocol core. Linux continues to use the Flutter interface adapted to Quick Send. Local discovery, HTTPS transfer, the generated TLS identity, certificate fingerprint verification, and receiver approval remain in LocalSend's Rust core.

Quick Send is based on [LocalSend](https://github.com/localsend/localsend). The Apache-2.0 license and upstream copyright notices are retained; see [NOTICE](NOTICE) and [LICENSE](LICENSE). The app's About screen also credits LocalSend.

Developer: Muhammed Alparslan Sancaktar · Ensignsoft.

## Android

Requirements: Node.js 22.11 or newer, JDK 21, Android SDK Platform 37, Android NDK 27.1.12297006, and the Rust toolchain pinned in `mobile/rust/rust-toolchain.toml`. Minimum Android version: Android 10 (API 29).

```sh
cd mobile
npm ci
npm run typecheck
npm test -- --runInBand
npm run lint
npm run android -- --mode debug
```

To build an APK without a connected device:

```sh
cd mobile/android
./gradlew assembleDebug
```

The APK is created at `mobile/android/app/build/outputs/apk/debug/app-debug.apk`. Android application ID: `com.ensignsoft.quicksend`. Android 13 and later request notification permission before background receive mode starts. Android 17 and later request local-network access before discovery.

## Linux

Requirements: FVM, Flutter 3.41.9, Rust 1.97.1, and GTK 3 development packages.

```sh
cd app
fvm flutter pub get
fvm dart run slang
fvm flutter analyze
fvm flutter test
fvm flutter build linux --release
```

The bundle is created under `app/build/linux/x64/release/bundle/`. Linux application identity: `com.ensignsoft.quicksend`.

## Development toolchains

- Flutter: version 3.41.9 pinned in [.fvmrc](.fvmrc) and used for Linux.
- Rust: version 1.97.1 pinned in [rust-toolchain.toml](rust-toolchain.toml); Android's isolated crate is pinned separately under `mobile/rust/`.
- React Native: 0.88, pinned in `mobile/package-lock.json`.

Quick Send adds no analytics, telemetry, or third-party service. Protocol and security boundaries for upstream updates are documented in [docs/UPSTREAM_SYNC.md](docs/UPSTREAM_SYNC.md).

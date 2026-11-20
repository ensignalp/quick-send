# Quick Send

Quick Send, aynı yerel ağdaki cihazlar arasında dosya ve mesaj aktarır; farklı ağlardaki cihazlar için internet üzerinden (iroh) aktarım da sunar. Android uygulaması React Native arayüzü ve LocalSend protokol çekirdeğine bağlanan bir JNI köprüsü kullanır. Linux uygulaması, Quick Send kimliğine uyarlanmış Flutter arayüzünü kullanmaya devam eder. Yerel ağ keşfi, HTTPS aktarımı, otomatik TLS kimliği, sertifika parmak izi doğrulaması ve alıcı onayı LocalSend Rust çekirdeğinde kalır.

Quick Send, [LocalSend](https://github.com/localsend/localsend) tabanlıdır. Apache-2.0 lisansı ve upstream telif bildirimleri korunmuştur; ayrıntılar için [NOTICE](NOTICE) ve [LICENSE](LICENSE) dosyalarına bakın. Uygulamanın Hakkında ekranında da LocalSend atfı bulunur.

Geliştirici: Muhammed Alparslan Sancaktar ·Founder Of Ensignsoft.

**İndir:** [GitHub Releases](https://github.com/ensignalp/quick-send/releases) — Android APK ve Linux AppImage. Uygulamalar yeni sürümleri imzası doğrulanmış olarak arka planda alır.

## Özellikler

**Her iki platformda**
- LocalSend protokolüyle uyumlu yerel ağ aktarımı (HTTPS, sertifika parmak izi doğrulaması); Quick Send ve LocalSend cihazları birbirini görür.
- Kimler paylaşabilir: Kapalı / Güvenilir cihazlar / Herkes. Al ekranı açıkken herkes paylaşabilir.
- Güvenilir cihazlardan gelen dosyalar onay sorulmadan alınır; kimliği değişen bir cihaza tek dokunuşla yeniden güvenilebilir.
- İnternet üzerinden gönderme (iroh): kod veya QR ile, mümkünse doğrudan, değilse şifreli aktarıcı üzerinden; yarıda kalan indirme devam eder; dosyalar ulaşınca paylaşım durur.
- Adrese gönder: IP adresi (noktalar yazarken eklenir) veya `#` ve adresin son sayısı.
- Gönderimden sonra "Gönderildi" onayı ve Al ekranına dönüş; alımdan sonra "Alındı".
- Son etkinlikler sayfası: resim, video, belge ve tarih filtreleri.
- Profil fotoğrafı (yalnızca o cihazda görünür), cihaz adı, alma PIN'i.
- İmzalı arka plan güncellemeleri (GitHub Releases, ECDSA P-256 imzalı SHA256SUMS) ve güncellemeden sonra "Yenilikler" ekranı.
- Açık/koyu tema, Space Grotesk yazı tipi, Türkçe ve İngilizce arayüz.

**Android**
- Ekran kapalıyken veya uygulama kapalıyken güvenilir cihazlardan alım (ön plan hizmeti, açılışta yeniden başlatma, pil optimizasyonu muafiyeti), "Alındı" bildirimi.
- Kendi dosya seçici (fotoğraf, video, belge sekmeleri), Android paylaş menüsü hedefi ve paylaş panelinde yakındaki cihazlar (Direct Share).
- İnternet kodunu QR olarak gösterme ve kamerayla QR okutma.
- Hızlı ayarlar kutucuğu, bildirimden kabul/ret.

**Linux masaüstü**
- Sistem tepsisinde çalışma, oturum açılışında başlatma, tek örnek (ikinci açılış dosyaları çalışan uygulamaya verir).
- Dosyalar (Nautilus) ve Dolphin sağ tık menüsünde "Quick Send ile gönder".
- GNOME/KDE'nin kendi dosya seçicisi (xdg-desktop-portal), son klasörü hatırlar.
- Başlık çubuğu sistem temasını ve ikonlarını izler; pencere 575 × 770 açılır.
- QR kod ve bağlantı ile tarayıcıdan indirme/yükleme, pencere gizliyken masaüstü bildirimleri, sürükle-bırak.

## Android

Gereksinimler: Node.js 22.11 veya üzeri, JDK 21, Android SDK Platform 37, Android NDK 27.1.12297006 ve `mobile/rust/rust-toolchain.toml` dosyasında sabitlenen Rust araç zinciri. Minimum Android sürümü Android 10 (API 29).

```sh
cd mobile
npm ci
npm run typecheck
npm test -- --runInBand
npm run lint
npm run web        # tarayıcıda arayüz önizlemesi (simüle veri)
npm run preview    # Expo Go ile telefonda önizleme (simüle veri)
npm run android    # Expo dev client: gerçek aktarım + hot reload
```

Ayrıntılar: [mobile/README.md](mobile/README.md). Bağlı bir cihaz olmadan APK üretmek için:

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

### Paketleme (RPM ve AppImage)

```sh
cd app && fvm flutter build linux --release --dart-define=QS_RELEASES_REPO=<owner>/<repo> && cd ..
packaging/rpm/build-rpm.sh          # build/rpm/RPMS/x86_64/quicksend-*.rpm
sudo dnf install ./build/rpm/RPMS/x86_64/quicksend-*.rpm
```

AppImage tarifleri `support/build/appimage/` altındadır ve CI'da Ubuntu 22.04 (glibc 2.35) üzerinde derlenir.

### Fedora güvenlik duvarı (firewalld)

RPM, `quicksend` adlı bir firewalld servisi kurar (TCP ve UDP 53317; port LocalSend protokolünden doğrulanmıştır). Servis otomatik açılmaz; cihazların birbirini görmesi için bir kez etkinleştirin:

```sh
sudo firewall-cmd --permanent --add-service=quicksend
sudo firewall-cmd --reload
```

Kaldırmak için `--remove-service=quicksend` kullanın. AppImage kullanıyorsanız aynı portları elle açın: `sudo firewall-cmd --permanent --add-port=53317/tcp --add-port=53317/udp`.

## Geliştirme araç zincirleri

- Flutter: Linux için [.fvmrc](.fvmrc) içinde 3.41.9 sürümüne sabitlenmiştir.
- Rust: Linux için [rust-toolchain.toml](rust-toolchain.toml) içinde 1.97.1 sürümüne sabitlenmiştir; Android JNI kasası da `mobile/rust/` altında bu sürüme sabitlenmiştir.
- React Native: 0.88; bağımlılıklar `mobile/package-lock.json` ile sabitlenir.

Quick Send analitik veya telemetri eklemez. Yalnızca "İnternet üzerinden" kullanıldığında iroh aktarıcısına (varsayılan n0) ve güncelleme denetiminde GitHub'a bağlanır. Upstream güncelleme sınırları ve protokol uyumluluğu [docs/UPSTREAM_SYNC.md](docs/UPSTREAM_SYNC.md) içinde açıklanır. Sürüm ve imzalama: [docs/RELEASE.md](docs/RELEASE.md). Testler: [docs/TEST_CHECKLIST.md](docs/TEST_CHECKLIST.md), güvenlik: [docs/SECURITY_CHECKLIST.md](docs/SECURITY_CHECKLIST.md).

---

# Quick Send

Quick Send transfers files and messages between devices on the same local network, and between devices on different networks over the internet (iroh). Android uses a React Native interface and a JNI bridge to the LocalSend protocol core. Linux continues to use the Flutter interface adapted to Quick Send. Local discovery, HTTPS transfer, the generated TLS identity, certificate fingerprint verification, and receiver approval remain in LocalSend's Rust core.

Quick Send is based on [LocalSend](https://github.com/localsend/localsend). The Apache-2.0 license and upstream copyright notices are retained; see [NOTICE](NOTICE) and [LICENSE](LICENSE). The app's About screen also credits LocalSend.

Developer: Muhammed Alparslan Sancaktar · Ensignsoft.

**Download:** [GitHub Releases](https://github.com/ensignalp/quick-send/releases) — Android APK and Linux AppImage. The apps fetch new versions in the background and install only signature-verified files.

## Features

**On both platforms**
- Local network transfers compatible with the LocalSend protocol (HTTPS, certificate fingerprint check); Quick Send and LocalSend devices see each other.
- Who can share: Off / Trusted devices / Everyone. While the Receive screen is open, everyone can share.
- Files from trusted devices arrive without a prompt; a device whose identity changed can be trusted again with one tap.
- Over the internet (iroh): send with a code or QR code, directly when possible and otherwise through an encrypted relay; interrupted downloads resume; sharing stops once the files arrive.
- Send to an address: an IP address (the dots appear as you type) or `#` and the last number of the address.
- "Sent" confirmation and return to Receive after sending; "Received" after receiving.
- Recent activity page with image, video, document and date filters.
- Profile photo (shown on that device only), device name, receive PIN.
- Signed background updates (GitHub Releases, ECDSA P-256-signed SHA256SUMS) and a "What's new" screen after updates.
- Light/dark theme, Space Grotesk typeface, English and Turkish interface.

**Android**
- Receiving from trusted devices with the screen off or the app closed (foreground service, restart after reboot, battery optimisation exemption) and a "Received" notification.
- Own file picker (photo, video, document tabs), Android share target and nearby devices in the share sheet (Direct Share).
- Show the internet code as a QR code and scan QR codes with the camera.
- Quick settings tile, accept/decline from the notification.

**Linux desktop**
- Runs in the system tray, start at login, single instance (a second launch hands its files to the running app).
- "Send with Quick Send" in the Files (Nautilus) and Dolphin context menus.
- The desktop's own file chooser (xdg-desktop-portal on GNOME/KDE), remembers the last folder.
- The title bar follows the system theme and icons; the window opens at 575 × 770.
- QR code and link for browser download/upload, desktop notifications while the window is hidden, drag and drop.

## Android

Requirements: Node.js 22.11 or newer, JDK 21, Android SDK Platform 37, Android NDK 27.1.12297006, and the Rust toolchain pinned in `mobile/rust/rust-toolchain.toml`. Minimum Android version: Android 10 (API 29).

```sh
cd mobile
npm ci
npm run typecheck
npm test -- --runInBand
npm run lint
npm run web        # browser UI preview (simulated data)
npm run preview    # phone preview with Expo Go (simulated data)
npm run android    # Expo dev client: real transfers + hot reload
```

Details: [mobile/README.md](mobile/README.md). To build an APK without a connected device:

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

### Packaging (RPM and AppImage)

```sh
cd app && fvm flutter build linux --release --dart-define=QS_RELEASES_REPO=<owner>/<repo> && cd ..
packaging/rpm/build-rpm.sh          # build/rpm/RPMS/x86_64/quicksend-*.rpm
sudo dnf install ./build/rpm/RPMS/x86_64/quicksend-*.rpm
```

AppImage recipes live in `support/build/appimage/` and are built in CI on Ubuntu 22.04 (glibc 2.35).

### Fedora firewall (firewalld)

The RPM installs a `quicksend` firewalld service (TCP and UDP 53317, verified against the LocalSend protocol). It is not enabled automatically; enable it once so devices can discover each other:

```sh
sudo firewall-cmd --permanent --add-service=quicksend
sudo firewall-cmd --reload
```

Use `--remove-service=quicksend` to undo. For the AppImage, open the ports manually: `sudo firewall-cmd --permanent --add-port=53317/tcp --add-port=53317/udp`.

## Development toolchains

- Flutter: version 3.41.9 pinned in [.fvmrc](.fvmrc) and used for Linux.
- Rust: version 1.97.1 pinned in [rust-toolchain.toml](rust-toolchain.toml); Android's isolated crate is pinned separately under `mobile/rust/`.
- React Native: 0.88, pinned in `mobile/package-lock.json`.

Quick Send adds no analytics or telemetry. It only contacts the iroh relay (n0 by default) when "Over the internet" is used, and GitHub for update checks. Protocol and security boundaries for upstream updates are documented in [docs/UPSTREAM_SYNC.md](docs/UPSTREAM_SYNC.md). Releases and signing: [docs/RELEASE.md](docs/RELEASE.md). Testing: [docs/TEST_CHECKLIST.md](docs/TEST_CHECKLIST.md), security: [docs/SECURITY_CHECKLIST.md](docs/SECURITY_CHECKLIST.md).

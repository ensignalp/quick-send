# Release guide / Sürüm kılavuzu

Releases are built by `.github/workflows/release.yml` when a tag such as
`v0.1.0` is pushed. It produces a signed Android APK + AAB, the x86_64
AppImage, the RPM and `SHA256SUMS.txt`, then creates a GitHub Release.

## 1. Bump the version (all must match; CI checks this)

- `app/pubspec.yaml` → `version: X.Y.Z+N`
- `support/build/appimage/AppImageBuilder_x86_64.yml` and `_arm_64.yml` → `version: X.Y.Z`
- `mobile/android/app/build.gradle` → `versionName "X.Y.Z"` (versionCode comes from the CI run number)
- `packaging/rpm/quicksend.spec` → add a `%changelog` entry

```sh
git commit -am "chore: release vX.Y.Z"
git tag vX.Y.Z && git push origin main vX.Y.Z
```

## 2. Android signing key (once)

Generate the upload/release keystore **outside the repository** and back it up
somewhere safe (password manager / offline storage). Losing it means you can no
longer update the app on devices that installed it.

```sh
keytool -genkeypair -v -keystore ~/secure/quicksend-release.jks \
  -alias quicksend -keyalg RSA -keysize 4096 -validity 10000
base64 -w0 ~/secure/quicksend-release.jks > /tmp/keystore.b64
```

Add these GitHub repository secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | contents of `/tmp/keystore.b64` (then delete the file) |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | `quicksend` (or your alias) |
| `ANDROID_KEY_PASSWORD` | key password |

Gradle reads `QS_KEYSTORE_PATH`, `QS_KEYSTORE_PASSWORD`, `QS_KEY_ALIAS`,
`QS_KEY_PASSWORD` from the environment only. Without them, release builds are
unsigned. **Never** commit `*.jks`, `*.keystore`, `key.properties` or passwords.

Local signed build:

```sh
export QS_KEYSTORE_PATH=~/secure/quicksend-release.jks QS_KEY_ALIAS=quicksend
read -rs QS_KEYSTORE_PASSWORD; read -rs QS_KEY_PASSWORD; export QS_KEYSTORE_PASSWORD QS_KEY_PASSWORD
cd mobile/android && ./gradlew assembleRelease bundleRelease
```

## 3. Update check

The in-app "Check for updates" button (About on Linux, Settings → About on
Android) sends one request to
`https://api.github.com/repos/<owner>/<repo>/releases/latest` **only when the
user presses it**. CI injects `<owner>/<repo>` from `github.repository`
(`--dart-define=QS_RELEASES_REPO` for Flutter, `QS_RELEASES_REPO` env for
Gradle). Local builds without it show "not configured" and make no request.
Release tags must be `vX.Y.Z` so version comparison works.

## 4. Before publishing

Run `docs/TEST_CHECKLIST.md` and `docs/SECURITY_CHECKLIST.md` against the
release artifacts.

---

**Türkçe özet:** `vX.Y.Z` etiketi atınca CI imzalı APK/AAB, AppImage ve RPM
üretip GitHub Release oluşturur. Keystore'u repo dışında `keytool` ile üret,
base64'ünü ve parolaları yukarıdaki dört GitHub Secret'a koy. Anahtarı veya
parolayı asla commit etme; kaybedersen uygulama güncellenemez, yedekle.
Uygulamadaki güncelleme kontrolü yalnızca kullanıcı butona basınca tek bir
istek atar.

# Release guide / Sürüm kılavuzu

Releases are built by `.github/workflows/release.yml` when a tag such as
`v0.1.0` is pushed. It produces a signed Android APK + AAB, the x86_64
AppImage, the RPM and `SHA256SUMS.txt`, then creates a GitHub Release.

## 1. Bump the version (all must match; CI checks this)

- `app/pubspec.yaml` → `version: X.Y.Z+N`
- `support/build/appimage/AppImageBuilder_x86_64.yml` and `_arm_64.yml` → `version: X.Y.Z`
- `mobile/android/app/build.gradle` → `versionName "X.Y.Z"` (versionCode is derived from it: X·10000 + Y·100 + Z, the same locally and in CI)
- `support/scripts/compile_windows_exe-inno.iss` → `MyAppVersion`, `cli/Cargo.toml` → `version`
- `packaging/rpm/quicksend.spec` → add a `%changelog` entry

```sh
git commit -am "chore: release vX.Y.Z"
git tag vX.Y.Z && git push origin main vX.Y.Z
```

## 2. Android signing key (once)

The Quick Send release keystore was created on the maintainer's machine:
`~/secure/quicksend-release.jks`, with alias and passwords in
`~/secure/quicksend-release.properties` (both mode 600, never committed). The
same values are stored as the GitHub secrets below. Back up `~/secure`.
For a local signed build: `set -a; . ~/secure/quicksend-release.properties; set +a`
then `./gradlew assembleRelease`.


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

## 3. Updates (manual check and background updates)

The in-app "Check for updates" button (About on Linux, Settings → About on
Android) sends one request to
`https://api.github.com/repos/<owner>/<repo>/releases/latest`. CI injects
`<owner>/<repo>` from `github.repository` (`--dart-define=QS_RELEASES_REPO` for
Flutter, `QS_RELEASES_REPO` env for Gradle). Release tags must be `vX.Y.Z`.

**Background updates** (Linux AppImage and Android APK, setting "Automatic
updates", on by default) additionally need an update signing key:

```sh
support/scripts/update-signing.sh genkey ~/secure/quicksend-update.pem
```

- Store the PEM file's contents as the repository **secret**
  `QS_UPDATE_SIGNING_KEY`; the release job signs `SHA256SUMS.txt` into
  `SHA256SUMS.txt.sig`.
- Store the printed public key as the repository **variable**
  `QS_UPDATE_PUBLIC_KEY`; builds embed it (`--dart-define` / Gradle env).
- Never commit the private key; back it up. Losing it means installed apps can
  no longer verify (and therefore never install) new releases.

What the apps do (every 12 hours at most, HTTPS only): read the latest release,
download `SHA256SUMS.txt`, its signature and the platform asset from this
repository's release downloads, verify the ECDSA P-256 signature with the
embedded key and the asset's SHA-256 against the signed list, and discard
anything that does not verify.

- Linux: replaces the running AppImage file atomically; the new version starts
  with the next launch. RPM installs are updated by the package manager instead.
- Android: also checks that the APK is signed with the installed app's
  certificate, then shows a notification; tapping it opens the system
  installer. Android always asks the user to confirm (the app was not installed
  by a store) and requires "Install unknown apps" for Quick Send.

Builds without the repository or the public key never download anything.

## 4. Before publishing

Run `docs/TEST_CHECKLIST.md` and `docs/SECURITY_CHECKLIST.md` against the
release artifacts.

---

**Türkçe özet:** `vX.Y.Z` etiketi atınca CI imzalı APK/AAB, AppImage ve RPM
üretip GitHub Release oluşturur. Keystore'u repo dışında `keytool` ile üret,
base64'ünü ve parolaları yukarıdaki dört GitHub Secret'a koy. Anahtarı veya
parolayı asla commit etme; kaybedersen uygulama güncellenemez, yedekle.
Arka plan güncellemeleri için `support/scripts/update-signing.sh genkey` ile
imza anahtarı üret: PEM'i `QS_UPDATE_SIGNING_KEY` secret'ına, çıktıdaki açık
anahtarı `QS_UPDATE_PUBLIC_KEY` değişkenine koy. İmzası ve SHA-256'sı
doğrulanmayan güncelleme asla kurulmaz.

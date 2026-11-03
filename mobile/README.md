# Quick Send for Android

The Android application is built with React Native 0.88 and React Native Paper's Material 3 components. Its Kotlin bridge calls the isolated Rust crate in `rust/`, which wraps the existing LocalSend protocol core without modifying its routes, payloads, or TLS fingerprint checks.

## Requirements

- Node.js 22.11 or newer and npm
- JDK 21
- Android SDK Platform and Build Tools 37
- Android NDK 27.1.12297006
- Rust 1.97.1 with `aarch64-linux-android` and `x86_64-linux-android` targets
- Android 10 (API 29) or newer

Configure `ANDROID_HOME` or `ANDROID_SDK_ROOT`, then from this directory run:

```sh
npm ci
npm run typecheck
npm test -- --runInBand
npm run lint
npm start
```

In another terminal, build and install the debug app:

```sh
npm run android -- --mode debug
```

Or build an APK directly:

```sh
cd android
./gradlew assembleDebug
```

The APK is written to `android/app/build/outputs/apk/debug/app-debug.apk`.

## Platform behavior

- Android 13 and later request notification permission before foreground receive mode starts.
- Android 17 and later request local-network access before device discovery.
- The app keeps TLS key material in Android Keystore-backed encrypted storage.
- Incoming files are written to the Downloads/Quick Send collection and retained only after the Rust core reports successful transfer verification.
- Background receive uses Android's `connectedDevice` foreground-service type for the local-network connection and requires the visible, user-started receiver mode.

The app only targets Android. Linux remains the Flutter application in `../app`.

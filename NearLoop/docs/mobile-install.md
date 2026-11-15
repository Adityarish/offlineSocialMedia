# NearLoop mobile handoff

The redesigned app uses the same Flutter screens on Android, iOS, and macOS.
It has a nearby-space feed, photo carousels, text posts, comments with an inline
composer, likes, private saved posts, search, a profile grid, drafts, and activity.
The member circles open profiles; they are not disappearing stories. Video,
Reels, direct messages, cloud followers, and camera QR scanning are not implemented.

## This Mac: Android

Java 21 and the Android SDK are installed locally under
`OfflineChatbot/.toolchains`, and licenses have been accepted. The Android build
scripts first download the pinned Gradle 8.14 binary ZIP using `curl` with retries,
verify its SHA-256 checksum, and cache it for the wrapper. This avoids the Java
wrapper download timeout. Subsequent builds reuse the installed distribution.
Run the export in Terminal:

```bash
source /Users/adityasingh/projects/OfflineChatbot/flutter-env.sh
cd /Users/adityasingh/projects/OfflineChatbot/NearLoop
bash scripts/export_mobile.sh android
```

The package update notices from `flutter pub get` are informational. They do not
cause Gradle download failures, and upgrading Dart packages is not required for
this fix. Initial downloads require access to `services.gradle.org`, `github.com`,
and `release-assets.githubusercontent.com`; Android/Maven dependencies also need
internet access. If the download fails, check your connection or proxy and rerun
the same command. The helper keeps only a fully verified ZIP. The wrapper JAR is
updated to 8.14 and has a 120-second network timeout for direct `flutter build` use.

For a fresh SDK installation, run `bash scripts/setup_android.sh` first and read
and accept the SDK licenses. The export script builds a development APK,
not an App Store/Play Store release. On success the installable file is:
`release/0.2.0/apps/NearLoop-0.2.0-android-debug.apk`.
The full folder on this Mac is
`/Users/adityasingh/projects/OfflineChatbot/NearLoop/release/0.2.0/apps/`.
Share the APK with Android friends; it cannot be installed on iPhones.
Copy it to your Android phone and open it, allowing installation from that file
source when Android asks. Or connect a USB-debugging-enabled phone and run:

```bash
adb install -r release/0.2.0/apps/NearLoop-0.2.0-android-debug.apk
```

## iPhone

1. Open `apps/nearloop/ios/Runner.xcworkspace` in Xcode.
2. Choose the Runner target, Signing & Capabilities. Enable automatic signing and
   select your Apple team. Keep the Keychain entitlement.
3. Connect your iPhone, trust the Mac, enable Developer Mode if iOS requests it,
   and select that iPhone as the run destination in Xcode.
4. From `apps/nearloop`, run `flutter devices`, then
   `flutter run --release -d YOUR_IPHONE_DEVICE_ID`.

A personal Apple team can be used for local device development subject to Apple's
provisioning limits. An exported development IPA additionally requires a suitable
provisioning profile and registered device. Once those are configured:

```bash
bash scripts/export_mobile.sh ios
```

The script only copies an IPA if Xcode actually exports one. An unsigned `.app`
or a ZIP of Flutter source cannot be installed directly on an iPhone. Nothing
is uploaded to TestFlight or the App Store by these scripts.

## First use

Create your profile, then open **Your space**. Create a space on a reachable Wi-Fi
interface or paste a private invitation from its host. Compare the host fingerprint
before joining. The host must remain open, especially on mobile. Allow local-network
access when asked. Posts start empty; preview/test fixtures are never inserted into
real user data. Offline actions appear in Activity until the host accepts them.

## Verification boundary

See `STATUS.md` for executed checks and current native build blockers. Headless
widget screenshots show real Flutter rendering with test-only data. They do not
prove iOS/Android device permissions, keychain access, or cross-device networking.

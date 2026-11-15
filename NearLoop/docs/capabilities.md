# Capability and dependency evidence

Official references were consulted during implementation; package platform claims are not device test results.

- Flutter 3.38.0 is a published stable release: https://docs.flutter.dev/release/release-notes/release-notes-3.38.0
- Platform/build-host requirements: https://docs.flutter.dev/platform-integration
- nsd 5.0.1 documents Android/iOS/macOS/Windows discovery and registration: https://pub.dev/packages/nsd/versions/5.0.1 . MIT; minimums listed by the package are Android 21, iOS 13, macOS 10.15, Windows 10 1903. Pinning and API usage were checked; native execution was not.
- flutter_secure_storage 10.3.4 documents all four target platforms: https://pub.dev/packages/flutter_secure_storage/versions/10.3.4 . BSD-3-Clause. OS access controls and release entitlements require testing.
- sqflite_common_ffi 2.3.6 and sqlite3_flutter_libs 0.5.40 provide the selected SQLite path: https://pub.dev/packages/sqflite_common_ffi/versions/2.3.6 and https://pub.dev/packages/sqlite3_flutter_libs/versions/0.5.40 . MIT. This older native-libraries line now has an EOL successor notice; evaluate migration after establishing a passing baseline.
- cryptography 2.9.0 (Apache-2.0), crypto 3.0.6 (BSD-3-Clause), basic_utils 5.8.2 (MIT), pointycastle 4.0.0 (MIT) supply signatures, hashes and local certificate generation. Basic Utils' published source requires Pointy Castle ^4.0.0: https://raw.githubusercontent.com/Ephenodrom/Dart-Basic-Utils/master/pubspec.yaml . Dependencies still need solver verification.
- path_provider 2.1.5, file_picker 10.3.3 and qr_flutter 4.1.0 are published packages; filesystem/native picker/QR rendering are not evidence of camera scanning or codec support. Each target's native behaviors remain untested. Package licenses are surfaced via Flutter's license registry after dependency resolution.
- Google Nearby Connections supports discovery and byte/file/stream exchange and abstracts Bluetooth/BLE/Wi-Fi: https://developers.google.com/nearby/connections/overview . This does not establish Bluetooth-only transport or desktop support. No adapter was enabled without implementation/device proof.
- Apple local-network privacy: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- Android radio permissions: https://developer.android.com/develop/connectivity/bluetooth/bt-permissions

Per-platform state: Android LAN/mDNS/key store unverified; iOS LAN/mDNS/key store unverified; macOS LAN/mDNS/key store unverified; Windows LAN/mDNS/key store unverified. Native Nearby is unimplemented on every target; strict BLE is unsupported by this build. No playback/transcoding codecs have been selected or shipped.

The source pin is not a claim of the newest dependency. Resolve and commit actual lockfiles, review dependency licenses/advisories, then verify release entitlements and every platform before distribution.

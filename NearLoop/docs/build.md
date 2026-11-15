# Toolchain and distribution

The app overrides `nsd_macos` and `nsd_ios` with copies in `third_party`, based on 3.0.0
with Flutter 3.38-compatible SwiftPM packaging. Its native implementation is
unchanged. Run `flutter pub get` after updating the checkout so Flutter includes
the `nsd-macos` and `nsd-ios` products in its generated package; see the vendored README.

Run from NearLoop. Flutter 3.38.0 is pinned in `.fvmrc`. Bootstrap checks `flutter --version --machine`, generates official native runners without overwriting existing application sources, adds network permissions/entitlements, and resolves dependencies. Preserve and review its generated diff. Commit the solver-generated lockfile after resolution succeeds. The macOS runner uses Flutter's Swift Package Manager integration, so verify the generated Swift package references and Xcode deployment settings after resolution.

```sh
python3 scripts/bootstrap.py
bash scripts/check.sh
bash scripts/build.sh android
bash scripts/build.sh macos
bash scripts/build.sh ios
```

On Windows: `python scripts/bootstrap.py`, then `./scripts/build.ps1 windows` in PowerShell. Windows requires Visual Studio C++ desktop tooling and its Windows SDK. Bundle the complete `build/windows/x64/runner/Release` directory including DLLs/data/Flutter assets; an EXE alone is not a release.

Current scripts build development Android APK, macOS debug app, iOS simulator app, or unsigned Windows release bundle. These are validation targets, **not** the signed production artifacts requested in the master plan. The CI matrix is source only and has not run. If this repository is committed below another repository root, move the workflow to that root and set the working directory appropriately.

For Android distribution, configure a private upload keystore and release signing in generated Gradle files, exclude all keys/passwords from Git, then run `flutter build apk --release` and `flutter build appbundle --release`. The generated project's default debug signing must not be presented as production signing. An AAB is a store-upload artifact, not a directly installable APK. Review target SDK local-network requirements and use system pickers rather than broad storage access.

For iOS, install full Xcode, select its developer directory, accept its license, configure an Apple development team/provisioning and test Keychain/local-network prompts on physical hardware. `flutter build ipa --release` requires a valid archive/export signing setup. A simulator build or unsigned app is not installable on arbitrary iPhones. TestFlight/App Store distribution requires appropriate Apple provisioning and account access.

For macOS, the minimum deployment target is 12.0. Open `apps/nearloop/macos/Runner.xcworkspace` in Xcode, select the Runner target, then Signing & Capabilities. Enable automatic signing and select your Apple development team. If necessary, add your Apple Account under Xcode Settings and create an Apple Development certificate through Manage Certificates. Keychain access groups require development signing; ad-hoc signing cannot supply this entitlement. Verify both network client/server sandbox entitlements, user-selected file access, keychain access groups and privacy prompts. Production delivery requires suitable distribution signing and (where applicable) notarization; neither was performed. Do not disable sandboxing/firewalls as a shortcut.

Windows firewall prompts should allow the intended private network only. Do not open router ports, configure UPnP or disable the firewall. Production code signing/installer packaging is still required before representing it as a distributed release.

`python3 tools/package_source.py` exports a clean source ZIP, SHA-256 checksum and a manifest with explicit not-built platform statuses. It does not collect or certify binaries. Extend this packaging step with verified artifacts and their signing/architecture metadata once real builds exist. Never publish stores/releases without explicit authorization.

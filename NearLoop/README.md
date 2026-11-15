# NearLoop

An offline-first, invite-only LAN social application under active development. Flutter application source, reusable protocol/storage/transport packages, tests, and build tooling live here. **This is not a verified four-platform release.** Read [STATUS.md](STATUS.md) for the exact implementation and verification boundary.

The app starts empty. No cloud login, hosted database, internet probe, public relay, STUN/TURN, or production seed content is used. Connections use a pinned self-signed host certificate and signed device requests. Nearby sharing gives recipients copies; removing access cannot retract copies already received.

## Mobile build and installation

The 0.2.0 interface adds a photo-first feed, carousels, inline comments, reaction states, profile/saved grids, and a mobile navigation bar. See [mobile-install.md](docs/mobile-install.md) for Android APK and iPhone installation steps. Source exports are not installable apps.

## Run after installing the toolchain

Install Flutter **3.38.0** and its platform prerequisites. This version is pinned, not claimed to be the latest. Dependencies use explicit published versions; the resolved lockfile is included. The local SDK bundles Dart 3.10 prerelease, which is allowed by the project SDK constraint.

```sh
cd NearLoop
python3 run.py
```

The launcher defaults to macOS on this Mac, reuses the local SDK under
`../.toolchains` when present, and otherwise finds Flutter on `PATH`. It works
from any directory when called by its full path. Use `python3 run.py --release`
for a release build, `python3 run.py -d <device-id>` for another device, or
`python3 run.py --dry-run` to inspect the launch command. Additional Flutter
options can follow `--`. Keep the Terminal open; `q` exits a debug run.

Use `flutter devices` and `flutter run -d <device-id>` for Android/iPhone or `flutter run -d windows` on Windows. iPhone/macOS require full Xcode; physical iPhone builds need a development team. On Windows use `python` if `python3` is not available. Bootstrap generates the four official native runners and applies networking/keychain configuration. The current checkout includes generated runners; bootstrap is only needed when regenerating them.

```sh
# From NearLoop/
python3 tests/test_schema.py
bash scripts/check.sh
bash scripts/build.sh macos       # or android, ios
# Windows PowerShell:
./scripts/build.ps1 windows
python3 tools/package_source.py
```

## First two-device demo

1. Run the application on two devices on a reachable private LAN. Create a display name on each.
2. On the host, open Your space → select a private interface address → Create nearby space. Prefer desktop hosting. A loopback address connects only on the same computer.
3. Copy the invitation to the other device using a private channel. Paste it under Join, then compare the full certificate fingerprint with the host display and confirm. The QR contains the same JSON; in-app camera scanning is not implemented.
4. Publish text, a small PNG/JPEG, and a comment. On the second device choose Download original. A successful download is SHA-256 verified. There is no preview/transcoding pipeline yet.
5. Disconnect, queue a post, restart, and rejoin using an invitation. Inspect Activity for pending/rejected writes. A restarted host can resume its last active hosted space using Create nearby space; clients must obtain the new endpoint invitation.
6. Try with internet disabled while LAN connectivity remains. Record results in `docs/testing.md`. This procedure has **not** been run on devices here.

## Repository

- `apps/nearloop`: adaptive Flutter application, native-runner generation targets, Dart tests.
- `packages/protocol`: identities, signatures, invitation validation, interfaces.
- `packages/local_store`: SQLite schema, transactions, event reducer, outbox, cached feed.
- `packages/transport`: embedded HTTPS host, pinned client, chunked file transfer.
- `scripts`, `tools`: bootstrap, validation builds, source packaging.
- `docs`: architecture, protocol, security, capabilities, testing, distribution.
- `.github/workflows`: native validation matrix and artifact aggregation; not yet executed.

This implementation intentionally reports unsupported/unverified capability states. See STATUS for unfinished core features; do not use it as a production security-reviewed release.

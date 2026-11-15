# Current status — NearLoop 0.2.0, 2026-11-16

The social UI is redesigned and verified through headless Flutter widget rendering.
**No Android APK or signed iOS IPA was produced in this session.** Native device
installation and two-device networking still require verification.

## Delivered in this update

- White/rose mobile interface with bottom navigation and a desktop sidebar.
- Fixed the profile counter row's 26-pixel overflow by constraining each counter and allowing centered labels to wrap. Verified at 390 and 320 logical pixels with Flutter's test font and platform font.
- Feed cards, original-photo carousels, text posts, likes/counts, bookmarks, caption editing and author/host removal actions.
- Inline comment sheet, disabled empty submissions, own-comment deletion, and visible offline/rejected comments.
- Explore search and grid, profile posts/saved grids, member profile sheets, profile editing, and refreshed onboarding/composer.
- Activity from committed local events and pending actions; blocked people filtered from the new grids and member circles.
- Ordered offline reaction intent (outbox row order), serialized/debounced drafts and draft loading scoped to the current space.
- Vendored nsd iOS/macOS 3.0.0 packaging fixes for Flutter 3.38 SwiftPM; native plugin sources remain unchanged.
- Source export includes platform assets, Gradle wrapper, licenses and local plugin overrides, excluding ephemeral platform paths and private signing files.

## Executed checks

- Flutter debug Dart asset bundle: **passed**, including the redesigned app.
- Analyzer library API over app source and tests: **0 errors**. The usual analysis server cannot create its home-directory cache in this sandbox.
- **4 tests passed** using the real Flutter test engine without a VM-service/test-server socket: offline reaction/bookmark persistence, phone navigation/profile/composer layout, inline offline comments, and desktop/narrow onboarding layout.
- Real Flutter screenshots inspected at `release/ui-preview/`. Data is test-only; no fixtures are inserted into the installed app.
- SQLite schema tests: **6 passed**.
- Standard `flutter test` launch is blocked by localhost socket permissions; `scripts/check_ui_headless.sh` runs the widget suite directly and checks its result log.

## Native export blockers

- Java 21 and Android command-line tools were installed under `OfflineChatbot/.toolchains`, with SHA-256 verification.
- Android platform/build-tools/NDK are installed and the user reports accepted licenses. On 2026-11-16, the Gradle download timeout was repaired: Android build/export scripts cache the pinned 8.14 binary ZIP with curl retries and SHA-256 verification; the wrapper JAR was updated to the verified official 8.14 JAR. Both official checksums matched, and `./gradlew --version` successfully launched Gradle 8.14 on Java 21. The subsequent `flutter build apk --debug --no-pub` passed distribution setup but stopped at `FileLockContentionHandler` with `java.net.SocketException: Operation not permitted` in this sandbox. Rerun the export in normal Terminal; no APK was produced in this session.
- The iOS native build stops when Xcode tries to write protected DerivedData/SwiftPM directories. The iOS Runner still needs an Apple team and device provisioning for an installable app.
- `scripts/setup_android.sh` and `scripts/export_mobile.sh` finish setup and export in a normal Terminal. Detailed instructions: `docs/mobile-install.md`.
- Source ZIPs, screenshots and Dart bundles are **not installable mobile applications**. The export manifest lists no absent binaries.

Stories, Reels/video, direct messages, cloud followers, profile photo upload, camera QR scanning and radio/device interoperability remain outside this implemented feature set.

---

The following is the original implementation record. Its environment and UI notes
are historical; the current evidence above supersedes them.

## Historical baseline — 2026-11-14

**Partial implementation, uncompiled. The master specification has not been fully satisfied.** No native build, running UI, two-process Dart exchange, physical-device test, throughput benchmark, signed installer or release binary has been verified.

## Environment evidence

- Initial workspace contained only `implementation.md`; no existing application or Git repository.
- `flutter` and `dart` are absent from PATH and were not found in the inspected development locations.
- `xcodebuild -version` reports that only Command Line Tools are selected; full Xcode is absent from `/Applications`.
- No Android SDK was found at the conventional user SDK path. Windows build tooling is unavailable on this macOS host.
- Flutter SDK metadata download failed: `curl: (6) Could not resolve host: storage.googleapis.com`.
- Local loopback socket bind failed with `PermissionError(1, 'Operation not permitted')` in this execution sandbox.
- No physical mobile devices were available to this session. Signing/provisioning was not configured.

## Source implemented; runtime verification outstanding

- Flutter light/dark adaptive sidebar/bottom-navigation UI, offline profile/name/bio, empty states, feed pagination, cached search, composer/drafts, text posts, PNG/JPEG carousels and alt text.
- Edit/delete own posts; comments/delete own comments; unique reaction state; local bookmarks/blocking; host post/member removal; invitation revocation; heartbeat member list.
- SQLite version-1 schema, foreign keys, indexes, WAL, transactional event reduction, persistent outbox, idempotency, conflict rejection, tombstones, space-scoped activity/cursors.
- Ed25519 identity in OS secure storage; request signatures, timestamp window, persisted nonce replay protection, invitation membership, per-request authorization, host certificate pinning with no public root trust fallback.
- Embedded HTTPS service bound to one selected private address; ephemeral-port fallback; explicit create/join/leave/disconnect; cached viewing after restart; polling with jittered reconnect backoff.
- Native mDNS adapter through `nsd`; minimal random advertisement names; manual invitation and QR display. Discovery does not establish trust.
- Bounded 256 KiB media chunks, disk-backed originals, SHA-256 completion checks, partial-file resume, PNG/JPEG header and dimension limits, server media quota, membership-protected media reads.
- Local data export without private keys, downloaded-original cache clearing, explicit local-data deletion.
- Native bootstrap configuration, Bash/PowerShell validation builds, CI matrix/aggregation, source packaging with manifest/checksum.

## Tests actually executed

- `python3 tests/test_schema.py`: **6 passed**. These test the actual SQL schema, not Dart runtime behavior.
- Bash syntax validation: `scripts/check.sh` and `scripts/build.sh` passed.
- Python compile validation: bootstrap, source packager, schema tests passed with temporary bytecode cache.
- Bootstrap prerequisite check: correctly stopped with actionable “Flutter is missing” error.
- Dart formatting, static analysis, Flutter tests, native builds and CI: **not run**.

Dart tests are provided for identity signatures, tampering, duplicate commits, author authorization, conflicts, tombstones, pagination, bookmarks/blocking, persistent outbox/drafts, reaction uniqueness, revoked membership, certificate pin rejection, unauthorized media requests, and image integrity. Their presence is not a passing result.

## Milestone ledger

1. Environment/reference inspection done. LAN text/image source and tests written; all four feasibility proofs remain blocked/unverified.
2. Identity, persistence, hosting/joining/membership source written; native key stores and lifecycle untested.
3. Feed/composer/images/social source written. Avatar, profile grid, video and previews remain incomplete.
4. Outbox, resume, authorization, moderation and diagnostics partly implemented; see remaining requirements below.
5. Nearby Connections and strict BLE experiments are **not implemented**. Do not label LAN transfers Bluetooth.
6. Later social features are deferred until the core is proven.
7. Build/test/source export tooling written. Native runners, transitive lockfiles, compiled artifacts and signed distribution remain blocked.

## Remaining required work

- Resolve dependencies, generate and commit native runners and real lockfiles; run Dart formatter/analyzer and fix all findings, then run Flutter and socket tests on an unrestricted development host.
- Prove two independent processes, second-device image transfer and mobile–desktop interoperability before treating any milestone as accepted.
- Add camera QR scanning and a structured manual endpoint form (currently paste invitation JSON); verify permission-denial/radio/network-change states rather than generic unverified capabilities.
- Replace polling with authenticated WSS if retaining the spec's live-channel requirement. Add snapshot recovery before pruning event history; history is currently retained indefinitely.
- Harden request/per-device rate limits, metadata quotas, membership admission limits, stream cancellation and graceful shutdown. The current concurrency/address limits are a starting implementation, not a DoS audit.
- Implement cache eviction, free-disk preflight, transfer concurrency/cancellation UI, resumable-transfer crash windows, garbage collection, quotas for drafts and cached downloads. Partial-file length is the present transfer checkpoint.
- Add sanitized thumbnail/preview generation, dimensions/duration in manifests, codec validation, short-video playback and original/preview choice. Current dimensions check is bounded header inspection, not full image decoding validation.
- Add avatar/profile grid, reaction counts/state presentation, received-event Activity UI, report-to-host workflow, mute/unblock management, desktop drag-and-drop and keyboard shortcuts, configurable retention, full accessibility QA.
- Improve draft autosave serialization, interrupted import cleanup, foreground host resume UX and explicit trust/key rotation. There is no identity backup/recovery UI.
- Verify local block filtering across every added surface. Current filters cover feed/search/bookmarks/comments; member list is not hidden by local blocking.
- Implement and device-test Android/iOS Nearby Connections; only then consider strict BLE framing/resume and verified capability states. No native Nearby plugin has been fabricated.
- Add comprehensive automated permission, network-change, cross-space, crash/restart, transfer-interruption, corrupted/oversized and widget/integration tests; run all acceptance scenarios in `docs/testing.md`.
- Signed APK/AAB, macOS app/notarization, Windows bundle/installer signing, Xcode archive/IPA need their respective build hosts and credentials. No store publishing performed.

The generated source archive is a development handoff, not an installable application. `release/0.1.0/manifest.json` explicitly marks all platform builds `not-built`.

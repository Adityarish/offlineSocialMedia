# UI validation for 0.2.0

Run `flutter test test/social_ui_test.dart` from `apps/nearloop` on an unrestricted
host. On this Mac, `bash scripts/check_ui_headless.sh` from NearLoop runs the same
suite using the native Flutter test engine without a test-server socket, writes
screenshots to `release/ui-preview`, checks the test result log and restores the
normal app asset bundle. Preview data exists only in isolated temporary databases.

# Acceptance runbook

## Automated checks

`python3 tests/test_schema.py` executes schema checks without Flutter. `bash scripts/check.sh` then resolves dependencies, formats Dart, analyzes and runs the Dart tests. The format step writes files; review and commit the result. Test names in `apps/nearloop/test/core_test.dart` describe actual assertions, not verified results. The TLS test runs one host/client within a test process and is not a two-process or radio proof.

Use an unrestricted development host for network tests. The implementation sandbox rejected even loopback bind; do not treat that as a source defect or as a passing networking test.

## Device matrix: every pairing currently NOT RUN

- Android–Android: LAN, images, lifecycle and Nearby not run.
- iPhone–iPhone: LAN, images, suspension and Nearby not run.
- Android–iPhone: LAN and Nearby interoperability not run.
- Android–Windows and Android–macOS: LAN not run.
- iPhone–Windows and iPhone–macOS: LAN not run.
- Windows–macOS: LAN not run.
- Native Nearby/BLE cases cannot be accepted until those adapters exist. Never substitute simulated peers for physical-device evidence.

For each run record date, OS/device model, app commit/toolchain, network topology, bound interface, permission state, discovery result, handshake result, original hash, observed latency and pass/fail. Do not record keys, invitation secrets, private content or raw media in diagnostic logs.

## Mandatory scenarios

1. Keep LAN connected but remove internet access. Create, join, post, comment and download. Neither app should contact an internet-check endpoint.
2. Block only multicast. Confirm discovery timeout, then join with manually copied invitation and verified pin.
3. Enable guest/client isolation. The manual invitation must fail with reachability diagnostics, never report a successful join.
4. Attempt events/media requests before joining, after revocation, for another space and with a guessed hash. Verify denial.
5. Upload a multi-chunk image. Interrupt mid-transfer, kill/restart client, rejoin, and verify completed original hash. Test host kill between rename and metadata commit; current reconciliation needs further hardening.
6. Lose a commit response and retry the identical operation. Exactly one host event/content item should exist.
7. Kill/restart both processes. Check SQLite integrity, cached feed, drafts and pending writes. Resume the previously hosted space explicitly, obtaining a new invitation if the port changed.
8. Delete a post, reconnect a stale client, and try edit/create with its old ID. Verify the tombstone prevents resurrection.
9. Deny local-network access; change Wi-Fi; enable VPN; fill disk; skew clock by more than five minutes. Confirm truthful errors and retained content. Nearby radio-off states cannot be accepted before the adapter exists.
10. Suspend an iPhone host/client. Confirm no claim of continued hosting and explicit foreground reconnection. No background push is expected.
11. Join two spaces in succession with overlapping names and event sequence numbers. Verify cached feed/search/outbox/media authorization stay scoped.
12. Block a member and verify feed/search/bookmarks/comments hide them. Member/profile/activity coverage is incomplete and must be finished before this acceptance case passes.

Also test a wrong but CA-trusted host certificate, wrong self-signed pin, request/body/path tampering, duplicate nonce, revoked/expired invitations, unsupported protocol, oversized metadata/chunks, invalid image dimensions, corrupt hash, unsupported formats, duplicate concurrent chunk writes, path traversal strings and host event replay.

## Performance targets — NOT MEASURED

Ten concurrent clients; roughly five-second discovery; roughly two-second metadata propagation; responsive pagination through 1,000 cached posts. Measure on named physical hardware. Polling interval alone is not a propagation benchmark. Cache/retention and denial-of-service acceptance remain open.

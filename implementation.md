NearLoop — Master implementation prompt
Copy this entire document into your coding agent, or attach it and ask the agent to implement it. This is a specification for an application to build, not a claim that the application already exists.
Your role and delivery standard
Act as a senior Flutter engineer, native mobile networking engineer, distributed-systems engineer, security engineer, and product designer. Build NearLoop: a polished, local-first social application with an Instagram-style experience for people who explicitly join the same nearby community through a local network or a supported nearby connection.

Deliver real source code, working networking, persistent data, tests, documentation, and platform build scripts in one repository. Do not stop at a plan, UI mockup, fake feed, or scaffold. Work in small executable milestones. Make routine implementation choices independently and record them. Ask only for genuinely blocking product decisions, credentials, signing access, or required hardware.

Use original branding, icons, and visual assets. Familiar social interaction patterns are welcome; do not copy Instagram assets or claim affiliation.
1. Product contract
The app must run on Android, iPhone/iOS, Windows, and macOS from one shared Flutter project, with native adapters where necessary.

The primary experience:
1. User creates an offline profile.
2. User chooses “Create nearby space” or “Join nearby space.”
3. The app discovers reachable app instances/spaces on the local network, or connects through a QR invitation/manual endpoint.
4. User explicitly joins a space and can browse its feed, publish media, react, comment, and interact with members.
5. Posts remain locally available according to cache and retention settings.
6. Drafts and pending actions survive restarts and reconnect safely.
No cloud account, paid API, hosted database, internet login, or internet connectivity may be required for the core LAN experience. Installation, dependency downloads, software updates, and distribution can require internet.

“Same Wi-Fi” means reachable app participants on a local network. It does not mean every device connected to a router is automatically a user. Never use an SSID, BSSID, public IP address, Bluetooth MAC, or network name as identity, authorization, or proof of proximity.

People connected to an Ethernet port on the same reachable LAN may also participate. Guest isolation, VLANs, hotspot policies, firewalls, VPNs, and multicast filtering can prevent connectivity. Show accurate diagnostics.

Discovery is not permission to read content. Membership and authorization are explicit. A nearby space has its own random ID, host identity, membership records, and access rules.
2. Technology and feasibility gate
Use Flutter/Dart as the default shared application stack. Start by checking current official documentation and the actual development environment. Pin a compatible stable toolchain and dependencies; do not invent package versions or APIs.

Suggested components, subject to verification:
- Riverpod for application state and dependency injection.
- go_router for navigation.
- SQLite through Drift for persistent local data and migrations.
- Application-private filesystem directories for media.
- HTTPS for authenticated control/media requests and WSS for live events.
- OS-native mDNS/DNS-SD/Bonjour discovery adapters.
- Platform-supported secure key storage.
- Kotlin and Swift native bridges for mobile nearby networking where a maintained Flutter adapter is insufficient.
- Desktop native adapters only when necessary.
Check every plugin for Android, iOS, Windows, and macOS support separately. A package supporting Bluetooth scanning is not evidence that it supports advertising, peripheral mode, file transfer, or interoperable peer sessions. Check licensing, maintenance, native SDK requirements, and desktop media codecs.

Before building the whole UI, prove:
A. Two processes can authenticate and exchange a persisted text post over LAN.
B. A second device can receive an image with verified integrity.
C. At least one available mobile-to-desktop pair can interoperate.
D. A native Nearby Connections experiment can exchange a small message between supported mobile devices, when physical devices are available.

Document results and missing hardware honestly. Keep LAN work progressing if nearby testing is blocked.
3. Network architecture: reliability first
Start with a host-and-clients architecture for each space. Prefer Windows/macOS for long-lived hosts. A foreground Android or iOS app may host a temporary session if supported and tested; never assume that a mobile OS will keep it alive in the background.

Implement reusable interfaces:
- DiscoveryService
- TransportAdapter
- SpaceSession
- IdentityStore
- MembershipService
- SyncEngine
- MediaTransferService
- LocalRepository
- CapabilityService
LAN transport — required baseline on all four platforms
A user explicitly starts hosting. The host runs an embedded authenticated service and advertises a versioned service such as _nearloop._tcp using platform-native discovery.

Provide three join methods:
- Discovered-space picker.
- QR invitation containing endpoint candidates, space ID, invitation details, and pinned host public-key/certificate fingerprint.
- Manual endpoint entry with an out-of-band identity verification step.
Support IPv4 and IPv6 where the environment supports them, multiple interfaces, changing addresses, occupied ports, disconnect/reconnect, and discovery timeouts. Bind only the interfaces needed for the selected space. Do not open router ports, enable UPnP, or expose an internet-facing server.

Manual IP/QR bypasses discovery failure; it cannot bypass client isolation or a firewall blocking actual traffic. Diagnose these separately.

Use authenticated encrypted connections. Do not globally disable certificate validation. If using a locally issued/self-signed certificate, verify its pinned fingerprint through the invitation or a user-confirmed authentication code. Rotate and revoke trust deliberately.

Do not use a cloud relay, public STUN/TURN service, or hidden internet fallback.
Nearby transport — implement and label actual support
Use Google Nearby Connections as the first candidate for Android/iOS nearby discovery and transport after verifying current SDK interoperability, device prerequisites, permissions, and adapter support.

This is Bluetooth/Wi-Fi-assisted nearby communication, not a promise of Bluetooth-only transfer. Do not label a transfer “Bluetooth” unless the SDK exposes reliable evidence of that transport. Do not assume OS Bluetooth pairing creates an application network.

Use the same application protocol over LAN and Nearby adapters. Negotiate protocol version, identity, membership, and transfer capability at connection time. Support a small host-centered topology before considering a mesh.

For strict Bluetooth-only mode, run a separate BLE GATT feasibility spike. If supported, limit the initial scope to text, small metadata, and tightly capped thumbnails. Implement framing, sequencing, acknowledgements, checksums, timeouts, flow control, and resume. Do not promise efficient video over BLE.

Windows/macOS nearby features are conditional on verified SDK/plugin/hardware support. Keep LAN complete regardless. Apple-only peer APIs are not automatically interoperable with Android or Windows. Check deprecation status before choosing any Apple framework.

Expose exact capability states: supported, unsupported, permission denied, radio off, hardware unavailable, service unavailable, and unverified. Never use simulated peers in production.
4. Membership, identity, and privacy
Create an offline identity with a cryptographically random identifier and a locally generated key pair. Keep private keys in the appropriate OS-protected storage. Display names can collide; use a short fingerprint for disambiguation.

Onboarding asks for display name, optional avatar/bio, and only contextual permissions. Do not require phone numbers, email, contacts, or GPS.

Default to invite-only spaces, with host approval or short-lived invitations. A short numeric code must be rate-limited and paired with authenticated key verification; it is not sufficient cryptographic protection by itself.

Support member removal, invitation revocation, roles, blocked identities, and explicit leave/disconnect. Separate device identity from a human identity; do not silently merge devices that share a name. Implement secure identity backup/restore before offering account recovery.

Define feed behavior:
- “Space feed”: posts authorized for the currently joined space.
- “Online now”: a presence filter with heartbeat expiry, not a location guarantee.
- “Saved/offline”: explicitly labeled cached content available after disconnection.
- Profiles can persist locally; visibility never grants access to another space.
- Switching networks disconnects or revalidates membership before synchronization resumes.
- Never automatically forward content from one space to another.
Tell users that nearby sharing delivers copies to other devices. Revocation stops future authorized access; it cannot reliably erase screenshots, exports, or copies already received.
5. Social features and interface
Build an attractive, responsive interface with a coherent original visual system:
- Mobile bottom navigation: Feed, Discover, Create, Activity, Profile.
- Desktop sidebar, centered feed, optional members panel, keyboard shortcuts, drag-and-drop media.
- Light/dark themes, readable typography, accessible contrast, scalable text, screen-reader labels, reduced-motion support.
- Skeletons, empty states, offline banners, transfer progress, retry controls, and useful error messages.
Core release:
- Profile creation/editing, avatar, bio, profile grid.
- Text posts, single images, photo carousels, and short video posts.
- Captions, local hashtags, image descriptions/alt text.
- Drafts, preview, publish, edit, delete own posts.
- Like/unlike, comments, delete own comments, bookmarks.
- Chronological feed with pagination and stable ordering.
- Local search over content the user is authorized to access.
- Nearby members, space information, join/leave controls.
- Activity generated from received events.
- Member mute/block and host moderation.
- Clear original-versus-preview download controls.
After the core is verified:
- Vertical short-video browsing.
- Stories with configurable expiry.
- Following and a following-filtered feed within authorized spaces.
- Opt-in direct messages and group messages.
- Multiple spaces, polls, pinned notices, desktop tray controls.
- English/Hindi localization infrastructure.
These later features must not delay a reliable first release. A button must perform a working action, be explicitly disabled with a reason, or be absent. Do not fill missing functionality with success toasts.

For messaging, explain delivered/read states precisely. Offline delivery requires a reachable authorized store-and-forward host or later reconnection. Do not claim end-to-end encryption when the host can read messages. If implementing E2EE, use a maintained, reviewed messaging protocol/library and document key verification, multi-device handling, and recovery.

For stories, hide expired content and garbage-collect local copies according to policy. Do not promise deletion of previously exported copies.
6. Data model and authorization
Use schemas for identities/devices, profiles, spaces, memberships, invitations, posts, media manifests, comments, reactions, bookmarks, moderation actions, events, outbox items, sync cursors, transfer checkpoints, and deletion tombstones. Add message tables only when messaging is implemented.

Include migrations, foreign keys, indexes, transactions, and schema versioning. Store media as files, not giant database blobs or base64 JSON.

All remote requests must enforce space membership and resource-level authorization, including media downloads, event subscriptions, searches, and resumed transfers. A content hash or guessed media URL must not bypass access checks.

Only an author can edit their post/comment; authorized moderators can hide/remove space content through explicit moderation events. Local hiding and host moderation are different operations. Private bookmarks stay local by default.

Separate development seed content from production data. Production must start clean.
7. Sync and recovery
Implement durable offline writes using an outbox and idempotency keys. An accepted host commit is authoritative for space ordering; clients may show optimistic pending UI.

Use an envelope with protocol version, event ID, space ID, authenticated actor/device ID, operation type, entity ID, expected entity revision, payload, and client time. The host validates and assigns a monotonic sequence and commit time. Do not trust client timestamps for authorization or ordering.

Implement:
- Host-issued sequence cursors and bounded incremental sync.
- Snapshot recovery when old cursor history is unavailable.
- Duplicate-event detection and idempotent retry.
- Explicit revision conflict handling for edits.
- Unique per-actor reaction state to prevent duplicate likes.
- Deletion tombstones that prevent stale-client resurrection.
- Heartbeats, stale-presence expiration, backoff with jitter.
- Transactional event/data updates and crash-safe checkpoints.
- Protocol negotiation and readable incompatible-version errors.
Retain unacknowledged local actions across restarts. On rejection, show the actual reason and preserve recoverable draft content.

When the host disappears, show “Space offline”; keep cached viewing and queue permitted actions. Version one must not claim automatic host failover. If host migration is later added, design authority transfer and split-brain prevention before enabling it. An explicit restored space is safer than silently starting conflicting hosts.
8. Media pipeline
Preserve original imported files unchanged. Generate separate thumbnails and optional lightweight previews; never overwrite an original with a compressed version.

A manifest includes content hash, size, MIME type, dimensions/duration where applicable, variant details, and availability. Identify posts separately from media hashes.

Transfer media as bounded streams/chunks with:
- SHA-256 verification and resumable checkpoints.
- Temporary partial files and atomic completion.
- Safe generated filenames; no peer-controlled filesystem paths.
- Size/dimension/duration limits and MIME/content validation.
- Disk-space checks, cancellation, bounded retries, and storage quotas.
- Backpressure, concurrency limits, lazy loading, thumbnail-first display.
- Authenticated range requests or equivalent resumable chunk requests.
- Safe handling of corrupt files and unsupported codecs.
Suggested configurable starting limits: 10 images per carousel, 20 MB per image, 60 seconds/100 MB per video, 500 MB cache, two concurrent media transfers. Treat these as product defaults, not platform guarantees.

Never load an entire large video into memory. Playback/transcoding must use maintained components with compatible licenses. If a codec cannot play on a target, report that accurately and offer an available original download.

Track local-only, uploading, available-on-host, preview-only, fully-downloaded, failed, and deleted states. A post with missing media must remain understandable.
9. Security and moderation
Threat-model malicious LAN peers and a compromised/curious host. Sharing a router does not make participants trusted.

Use reviewed cryptographic libraries. Include replay protection, authenticated sessions, token expiry/revocation, invitation throttling, input validation, per-peer resource limits, and authorization checks on every operation.

Protect against path traversal, oversized/decompression payloads, malicious archives, HTML/script injection in rendered content, unauthenticated event subscriptions, and denial-of-service through transfer queues. Never execute received content.

Minimize discovery metadata. Do not advertise names, email addresses, membership lists, or stable personal identifiers unnecessarily. Exclude secrets, message content, tokens, and raw media from diagnostic logs.

Block/mute must be applied consistently to the feed, profiles, search, activity, and messages. Host moderation can remove members/content; local blocking cannot stop a determined person creating another identity, so document this limitation.

Provide reporting to the current space moderator where one exists. Do not pretend there is a cloud moderation team. Include export/delete-local-data controls, cache clearing, space retention settings, and a concise privacy explanation.
10. Platform behavior
Android:
- Check permissions against the chosen target SDK: local networking, nearby devices, Bluetooth scan/connect/advertise, notifications, and media access as actually needed.
- Prefer system photo pickers over broad storage permissions.
- Check Google Play services/device support if Nearby requires it.
- Handle battery saver, background restrictions, and foreground-service rules accurately.
- No silent radio toggling or fictional programmatic hotspot support.
iOS:
- Configure local-network usage descriptions, Bonjour service declarations, and Bluetooth descriptions when required.
- Request entitlements only when the implemented networking path needs them.
- Expect suspension/background limitations; checkpoint transfers and reconnect on foreground.
- Do not claim always-on background hosting, discovery, or offline push.
- Test physical devices for nearby radio interoperability.
macOS:
- Configure network client/server entitlements and relevant local-network/Bluetooth permissions for the selected deployment.
- Test sandboxed release behavior and secure storage.
Windows:
- Check firewall/network profile behavior and adapter capabilities.
- Explain permission prompts; do not disable the firewall.
- Bundle all required runtime libraries and Flutter assets.
For every platform, distinguish local network reachability from internet status. An internet-check endpoint must not gate LAN functionality.
11. One source folder and release exports
Deliver one repository, NearLoop/, containing:
- apps/nearloop/ — shared Flutter app plus android/, ios/, windows/, macos/.
- packages/protocol/, packages/local_store/, packages/transport/.
- packages/native_nearby/ if a custom plugin is needed.
- tests/, integration_test/, tools/, scripts/, docs/.
- CI workflows, pinned toolchain configuration, lockfiles, licenses.
- README.md, STATUS.md, architecture/security/protocol/build/testing documents.
Provide build scripts for PowerShell and Bash. They must check the host OS, toolchain, signing prerequisites, and expected outputs, then fail with useful messages.

Collect available outputs into release/<version>/:
- android/: release APK and AAB.
- windows/: complete executable bundle and optionally installer/MSIX.
- macos/: .app and optional DMG/archive.
- ios/: Xcode archive and signed IPA when credentials/provisioning allow.
- source/: clean source archive.
- manifest.json and checksums with version, architecture, build status, and signing status.
Do not treat one Windows EXE without its required DLLs/assets as a complete release. Do not present an AAB as directly installable like an APK. Do not present an unsigned/simulator iOS build as installable on an arbitrary iPhone.

Use the appropriate build hosts: macOS/Xcode for iOS and macOS; Windows tooling for Windows. Android can be built on an appropriately configured supported host. A single source folder does not mean a single computer can produce every signed platform artifact.

Provide a CI build matrix and aggregation workflow to collect artifacts from the different runners. Keep unsigned build validation separate from signed distribution. Document Apple provisioning, development testing, TestFlight/App Store paths, macOS signing/notarization, and Windows signing without promising free unrestricted distribution.

Never store credentials or signing keys in source control. Do not publish to stores or external services without explicit authorization.
12. Acceptance tests and measured goals
Automate unit/widget/integration coverage for identity, membership, permissions states, authorization, feed pagination, persistence, outbox retry, conflicts, tombstones, deduplication, transfer resume, and corrupted/oversized input.

Provide real-device test instructions and a results matrix for:
- Android–Android, iPhone–iPhone, Android–iPhone.
- Android–Windows, iPhone–macOS, Windows–macOS.
- Remaining mobile–desktop pairs for complete four-platform LAN coverage.
- Nearby tests only for combinations the adapter actually supports.
Mandatory scenarios:
1. Disable internet while retaining LAN connectivity; create/join/post/comment/download.
2. Connect with QR/manual endpoint when discovery alone is blocked.
3. Demonstrate the diagnostic when client isolation prevents any connection.
4. Reject an unauthorized member and unauthorized media fetch.
5. Interrupt a large transfer, restart, resume, and verify original-file hash.
6. Repeat an operation after a timeout without duplicating it.
7. Kill/restart the app and host without corrupting stored data.
8. Delete a post, reconnect a stale client, and prevent resurrection.
9. Deny permissions, disable radios, change networks, fill disk, and simulate clock skew.
10. Suspend an iPhone session and confirm truthful status/recovery.
11. Switch spaces and confirm no cross-space data leakage.
12. Block a user and verify all applicable surfaces.
Initial engineering targets, not guarantees: 10 concurrent clients, discovery within roughly 5 seconds on a friendly LAN, metadata propagation within roughly 2 seconds on a healthy foreground connection, and responsive browsing of 1,000 cached posts through pagination. Benchmark on named hardware and record observed values; do not invent measurements.

Run formatting, static analysis, meaningful automated tests, and builds supported by the available host. Simulation tests are not proof of radio interoperability. Report all untested device/OS combinations.
13. Execution order and final handoff
Milestone 1: inspect environment, verify dependencies, write capability matrix, prove secure LAN text/image exchange.
Milestone 2: offline identity, local persistence, host/join, authenticated space membership.
Milestone 3: real feed, composer, media transfer, profiles, reactions, comments.
Milestone 4: retries, resume, permissions, moderation, security checks, diagnostics.
Milestone 5: verified mobile nearby adapter; clearly scoped strict-BLE experiment if feasible.
Milestone 6: later social features that can be completed reliably.
Milestone 7: platform packaging, build matrix, documentation, acceptance verification.

At each milestone, leave a runnable state and record completed/blocked/untested work in STATUS.md. Do not repeatedly ask whether to continue.

At handoff provide:
- Repository and actual generated artifacts.
- Exact local run/build commands and first two-device demo procedure.
- Implemented features and verified platform/transport matrix.
- Tests actually run and observed results.
- Remaining blockers with specific next steps.
- Honest limits around Bluetooth, background operation, host availability, signing, and retained copies.
Start now by inspecting the workspace/toolchain, writing the capability matrix, and implementing the first real LAN vertical slice. Continue through the authorized implementation; do not finish with architecture alone.
Official references to verify during implementation
These references informed the design; recheck their current requirements for the pinned toolchain:
- Flutter platform integration and build hosts: https://docs.flutter.dev/platform-integration
- Flutter desktop support: https://docs.flutter.dev/platform-integration/desktop
- Flutter iOS release workflow: https://docs.flutter.dev/deployment/ios
- Flutter macOS release workflow: https://docs.flutter.dev/deployment/macos
- Google Nearby platform/interoperability: https://developers.google.com/nearby/
- Nearby Connections overview: https://developers.google.com/nearby/connections/overview
- Nearby Android setup: https://developers.google.com/nearby/connections/android/get-started
- Nearby iOS setup: https://developers.google.com/nearby/connections/swift/get-started
- Apple local-network privacy: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- Android Bluetooth permissions: https://developer.android.com/develop/connectivity/bluetooth/bt-permissions
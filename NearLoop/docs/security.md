# Security and privacy boundary

Treat router neighbors as untrusted. Discovery is not admission. Names are not identities. Sharing a space gives the host and authorized participants copies; this is transport encryption, not E2EE. A compromised host can read/alter content and lie about ordering. Users must compare the host fingerprint through an independent trusted channel.

The client uses an empty root trust store and accepts only the invitation's exact certificate fingerprint on the expected host/port. Redirect following is disabled. There is no global insecure certificate override. Identity seeds and TLS private keys go to flutter_secure_storage; native keychain/keystore support must still be validated on every target. SQLite content itself is not encrypted at rest.

All request paths, including media, authenticate signatures and membership. Public key-derived actors cannot be overridden in a payload. The request signature covers method, path/query, body digest, timestamp and nonce. Authorization is repeated at event commit. Deleted post IDs cannot be recreated. A removed identity cannot rejoin through an old invitation; someone creating a different key is a different identity and can still be invited.

Request streams are bounded and timed; host concurrency is limited to sixteen requests and address request rate is bounded. Invitations contain high-entropy secrets; there is no numeric-code authentication. Media names are generated exclusively from space/hash values, never peer filenames. Media size and header dimensions are bounded; no received scripts, HTML, archives or executables are rendered or executed.

Unfinished hardening: detailed threat review, denial-of-service tests, CPU/resource budgets, full content decoding validation, file-system crash reconciliation, secure trust rotation, per-device quotas, disk preflight and controlled cache eviction. Generic failures intentionally avoid logging keys, invitation secrets or message bodies. This source is not security-audited or production-ready.

Local export omits signing keys and invitation secrets but includes cached content/drafts/outbox, which are sensitive. Local deletion cannot delete copies on other devices. OS backups are disabled for Android application data; verify release platform behavior.

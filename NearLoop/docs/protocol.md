# NearLoop LAN protocol v1

A private HTTPS endpoint serves exactly one random space ID. Invitation JSON includes `v`, `endpoint`, `space`, `pin` (lowercase SHA-256 of DER certificate), and a 256-bit `secret`. Invitations expire after an hour and admit at most ten new members. Discovery advertises only a transient name and service/port; content is unavailable without membership.

Every request carries `x-nearloop-version`, `x-key` (base64 Ed25519 public key), `x-time` (milliseconds), `x-nonce` (256-bit base64url), and `x-signature` (base64 Ed25519 signature). Signature input is UTF-8 lines joined by LF: `nearloop/1`, HTTP method, exact path plus query, lowercase SHA-256 of request body, time, nonce. The identity is the SHA-256 of decoded public key bytes. Clock skew over five minutes is rejected. Nonces are persisted for ten minutes. TLS pinning authenticates responses; the host is trusted to assign commits.

Routes under `/spaces/{space}`:

- POST `join`: invitation secret plus display name, signed by the joining device.
- POST `events`: `v,id,space,actor,op,entity,revision,payload,clientTime`. Server returns `seq` and `committed`.
- GET `events?after=N`: up to ten ordered events, bounded incremental replay.
- GET `members`: active membership records and heartbeat times.
- POST `leave`: explicit member departure.
- POST `invite/revoke`: host-only invitation revocation.
- PUT `media/{sha256}?offset=N&size=N`: signed raw chunks up to 256 KiB. Response supplies authoritative resume offset and completion.
- GET `media/{sha256}?offset=N`: authorized chunk read. Membership plus accessible post reference or upload ownership is required.

Supported operations: post.create/edit/delete/moderate, comment.create/delete, reaction.set, profile.set, member.remove. Expected revisions protect edits/deletes. Host moderators may explicitly remove others' content. The host never accepts an envelope actor different from the authenticated request actor.

A client retries the same operation ID and body using a new request nonce/signature. Media attempts negotiate offset; source hashes are computed by streaming. A partial file is a byte checkpoint. Missing originals produce a readable error; metadata remains viewable.

No account recovery, E2EE, delivered/read message protocol, WebSocket endpoint or host failover is advertised by v0.1.0 source.

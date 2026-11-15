# Architecture and recorded decisions

The host is authoritative for its space. Clients retain their own SQLite materialization and durable outbox. Identity is a device key, not an SSID, IP, display name or human account. A device may have cached multiple spaces, but only one session is active at a time. Hosting uses the same request path as remote publishing.

`protocol` has no Flutter dependency. `local_store` uses sqflite_common_ffi with packaged SQLite libraries; this was chosen instead of Drift to keep the first event reducer and schema inspectable without generated code. `transport` uses Dart IO HTTPS and streaming files. The app uses ChangeNotifier rather than Riverpod/go_router for the five-tab single-session flow. These are implementation choices, not evidence of acceptance.

Incoming commits validate membership, actor identity, operation, resource ownership and revision inside a transaction; insertion of the ordered event and mutation of the materialization share the transaction. Failed mutations roll back the event. An identical idempotency ID/body returns the prior commit. Deletes retain a tombstone. Reactions have a deterministic per-actor/post identity. Feed order is original host sequence, not client time, so editing does not bump a post.

Remote event replay and cursor updates share one client transaction. Remote activity sequences are scoped by space and kept separate from this device's host-authoritative event sequence allocator. Event history is never pruned yet, so normal replay uses retained history; snapshot recovery remains required before pruning. Polling is used instead of WSS in this implementation.

Images are original files. Wire chunks are binary, not base64. A local draft copies imported files into private storage before queuing. Uploads complete before the post is committed, and the final wire envelope is persisted before transmission to preserve retry identity. Downloads use temporary files and SHA-256 verification before rename. No image preview, video transcoder or content execution is present.

When a mobile app pauses, it explicitly disconnects rather than suggesting background hosting will continue. On resume it can reconnect through an invitation. No automatic host failover, split-brain authority transfer or internet fallback exists.

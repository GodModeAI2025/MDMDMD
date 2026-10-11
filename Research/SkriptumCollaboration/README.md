# Scriptum collaboration replica (R08, independent module)

This package owns one actor-isolated Automerge page replica. It is not an authenticated sharing backend or an integrated native app feature. No server, identity verification, transport, role enforcement, scheduler or UI is implemented here.

## Dependency evidence

Official `automerge/automerge-swift` **exact 0.7.2**, tag revision `aa45d17ac92cef2b8ded63b47e65a28dc85e3418`. Release artifact `automergeFFI.xcframework.zip` downloaded and independently SHA-256 checked:

```
10245378e74229b026f689b039d7df3cf17aeed353706d5f420dfd164f283a86
```

The value equals the checksum in the upstream 0.7.2 `Package.swift`; there is no checksum override. SwiftPM independently verifies the artifact. Upstream APIs were read from the actual pinned `Document.swift`, `ScalarValue.swift`, `TextEncoding.swift`, Rust `doc.rs`, and the pinned Rust core `automerge.rs`/`exid.rs`.

Two upstream details are covered by implementation and tests: byte loading resets text encoding, so loading is followed by merge into an explicitly UTF-16 document; incremental loading permits partial data, so incoming chunks are strictly loaded together with the accepted save before merging. Object IDs are compared against historical references inside the candidate, avoiding serialization-dependent actor-index hints while rejecting object replacement.

## Boundary

- `ReplicaIdentity` binds library, Space and page UUIDs. Every current conflicting identity value must match the expected identity. This prevents accidentally accepting another page, but does not grant authorization: authenticated owner/editor/viewer enforcement belongs to the backend.
- `PageReplica` owns the mutable Automerge document. Callers receive immutable value snapshots, opaque heads and bounded binary payloads.
- The schema keeps stable UUID-keyed block records, real Automerge text objects, tombstones, edit counters and predecessor positions. LF/CRLF and Unicode normalization variants are retained as UTF-8 bytes. No source parsing or newline insertion occurs here.
- Text edit ranges use UTF-16 code units. Both ends must be valid scalar boundaries; splitting a surrogate pair is rejected. Combining sequences may be edited at scalar boundaries, consistent with native text indexing.
- Incoming Automerge bytes are applied to a candidate fork, validated and bounded, then published. A rejected candidate leaves the accepted state untouched.
- Deletion is a tombstone, not removal of the text object. Concurrent edit/delete creates an observable conflict with recoverable text. Explicit restore makes that text active again.
- Ordering uses predecessor references, deterministic priority and UUID tie-breaking. Conflicting moves and cycles are surfaced. Normalization never drops or duplicates a block.

## Integration remains open

Native autosave and durable pending-change queues; authenticated multi-user transport; library isolation on server; inherited rights and revocation; collaboration UI; actual two-device/server proof and production memory/latency stress. The wrapper limits incoming bytes and accepted state, but the upstream binary parser allocates before schema validation: its decompression resource limits must be assessed before accepting untrusted Internet traffic.

No completion claim for R08 is implied by standalone package tests.

## Verification

9 permanent Swift Testing tests pass on the real package with macOS arm64. Tests exchange actual encoded changes and full saves between independent forks in opposite merge directions; exercise UTF-16 reload, normalization bytes, CRLF, malformed suffix rollback, identity and container replacement rejection, tombstone restoration, concurrent insert/reorder and cycle visibility, and size rollback. Verification summary: [VERIFICATION.md](VERIFICATION.md). Raw build logs remain in the task scratch directory.

```sh
swift test --disable-sandbox --disable-keychain --disable-netrc --build-system native --scratch-path /private/tmp/skriptum-collaboration-build
```

The native SwiftPM build system was used because this host's default builder stalls during cache purging. Credential lookup was disabled for this public dependency after a sampled process blocked in macOS Keychain; this changes no artifact validation. iOS compilation, app linking, simulator and device behavior are not established by these module tests.

Encoded change delivery requires causally complete changes (or a complete saved document); this module does not implement acknowledgment, durable retry, or an out-of-order pending queue. A future authenticated transport must use dependency-aware synchronization and persist incoming/outgoing pending data before acknowledgment. Raw `receive` is not a production transport endpoint.

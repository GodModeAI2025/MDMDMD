# R08 collaboration — independent replica implementation wave

The full requirements remain R01–R12. This wave builds the actual merge engine; it does not claim that sharing, authentication, inherited server permissions or deployment already work.

## Decision
Use the official Automerge Swift package pinned to 0.7.2 with its verified SwiftPM artifact checksum and resolved revision. The upstream Swift implementation supports text editing, document forks, merging and binary change exchange. Configure text indexes as UTF-16 to match native text input. Do not implement a new text CRDT.

Primary sources inspected: [official Swift package](https://github.com/automerge/automerge-swift/blob/main/Package.swift), [Document API](https://automerge.org/automerge-swift/documentation/automerge/document/), [sync API](https://automerge.org/automerge-swift/documentation/automerge/sync/).

## Scope and files
A standalone package under Modules/SkriptumCollaboration, with its own Package.swift, resolved dependency and permanent tests, owns the replica actor and schema. It must not edit the native application's Sources, project.yml, Package.swift or Xcode project while the current native UI verification is running. Native integration is a following wave.

## Contracts
- One document represents exactly one page identity. Reject importing changes that change the page or space identity before publishing a new state.
- Block UUIDs identify stable block records; text is an Automerge text object, not a last-writer-wins String scalar. Ordered block references may be normalized deterministically after concurrent reorder, with observable ordering conflicts.
- UTF-16 edit ranges must reject surrogate splits. Untouched source bytes, LF/CRLF and Unicode normalization distinctions remain exact.
- Save/load and encoded change exchange use real Automerge data. Apply incoming data to a candidate fork, validate schema and size limits, then publish atomically. Invalid data cannot replace the accepted replica.
- Concurrent deletion/edit must retain recoverable text and surface a conflict; no silent content discard.
- An actor owns mutable document state. Expose value snapshots and bounded Data, not the live document instance.

## Evidence required
Write and run tests against the real package for two peers concurrently editing the same block, offline merge convergence in opposite orders, exact Unicode/CRLF preservation, edits and moves retaining IDs, concurrent deletion/edit, save/reload, wrong-page rejection and rejected-candidate rollback. Verify the actual artifact checksum; never override a mismatch. Record platform/typecheck limitations.

## Following waves still required
Authenticated backend transport with owner/editor/viewer permissions and inheritance; account and library isolation; durable local pending changes; real multi-client server/device proof; explicit sharing UI; scheduling/budgets/authorized execution for R09; physical provider tests. No endpoint or permission placeholder counts as completion.

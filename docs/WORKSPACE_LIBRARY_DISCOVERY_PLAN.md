# Authenticated library discovery

Base: `b9664caccb6ccd4b0c1b3b618bf1f9c745d65c13`. This is the contract stage needed before the native cloud-library picker. R08 remains open until actual selection, binding, permission reconciliation and simultaneous editing work. R06 deployment and Apple gates remain separate.

## Current gap

The gateway supports only POST at `/libraries`. The Swift client can create a library but cannot discover accessible libraries or read library metadata. The account inspector therefore correctly offers no arbitrary UUID input or fake connection action. Library titles already exist as server metadata, limited to 4096 UTF-8 bytes; they must be disclosed only after actual authorization.

## Requirements

- WD01: An authenticated account can enumerate its owned libraries and libraries with effective access at the library root. Unrelated libraries and grants limited to an individual space/page do not disclose library-root metadata through this API. Narrow shared-resource discovery remains a required subsequent R08 stage.
- WD02: Every row reflects actual session admission and inherited/capped library-root permissions. Revoked, expired, legacy-disabled or tombstoned sessions cannot obtain metadata. A tombstone fixture must respect the existing account constraint: a non-null disable time needs an allowed disable reason, and an account-deletion tombstone uses `account-delete`. A concurrent membership revocation must be rechecked after acquiring the library lock.
- WD03: Pagination has a fixed small page size, stable UUID order and a validated UUID cursor. No total-count query, unbounded collection, client-selected limit or credential in query parameters.
- WD04: Reading a specific library returns metadata only for an admitted root member/owner. Missing and inaccessible library IDs have the same public 404 response. A forged cursor or library ID grants no access. The role uses the existing wire vocabulary; rank `owner` is a permission level and does not assert or transfer the immutable owning-account identity.
- WD05: The Swift identity actor provides strict bounded typed metadata methods; logout/replacement fences stale responses. No credential, proof or reauthentication receipt is exposed by metadata DTOs.
- WD06: Actual HTTP/PostgreSQL tests prove role filtering, pagination, title bounds, denial and concurrency. Client tests prove malformed/oversized/unknown-field/duplicate-ID responses fail closed. A real signed fixture validates the new wire contract before native activation.

## Decisions and contract

1. `GET /libraries?after=<UUID>` returns `{ "libraries": [{ "libraryID": "UUID", "title": "text", "role": "viewer|editor|owner" }], "nextAfter": "UUID|null" }`. The cursor is absent on the first request. Reject repeated, unknown or malformed query parameters. The cursor is a position, never authorization.
2. A page examines at most 8 rows plus one look-ahead candidate. `nextAfter` advances past the last examined row when another candidate exists, even if concurrent revocation removes a returned row. Clients handle an empty page with a non-null advancing cursor. Repeated/non-advancing cursors fail closed.
3. Titles retain their exact existing content. A 256 KiB response ceiling covers eight maximally JSON-escaped 4096-byte titles and metadata overhead. Identity replies retain their existing 24,576-byte default limit; only these validated read methods use the larger limit.
4. `GET /libraries/<UUID>` returns one strict metadata object with the same fields and limit. No page bodies, memberships of other people, keys or ownership identifiers are added.
5. Reuse real authentication, library locking and current-session rechecks, and preserve the effective-role semantics. Do not call the current generic `rank()` helper: it materializes all root/space/page memberships for a library. Discovery must query only the root membership for the exact account/library, using the existing root uniqueness/index, and calculate the same owner/capped-root role from that bounded result. Cap the SQL candidate IDs at 9 before fetching titles or acquiring library locks; no all-memberships array or unrestricted intermediate JavaScript collection. Lock/revalidate in UUID order. Existing transaction limits are 5 seconds per statement/lock, not an end-to-end deadline; this stage must not claim a total 5-second request bound. Authorization failures must not leak title bytes in public errors or logs.
6. Library-root grants alone authorize this root listing. Do not promote a page/space grant into access to its siblings or parent metadata. A later scoped-resource discovery API is necessary for those shares; this stage cannot claim complete sharing.
7. Add typed `WorkspaceLibraryMetadata` and `WorkspaceLibraryMetadataPage` values and `WorkspaceIdentityClient.listLibraries(after:)` / `libraryMetadata(id:)`. Capture the actor's actual admission before requests and check it before returning. Native adapters must additionally carry the durable admission ticket and exact window/facade generation before activating these APIs in the app.
8. The current strict JSON boundary accepts objects/scalars only. Add explicit opt-in arrays with at most 8 entries while retaining depth 4, node count 64 and duplicate-key validation before Foundation materializes values. Existing identity/envelope parsing retains its default array rejection. Only the metadata page parser opts in; metadata body size is checked before structural parsing.

Rejected: arbitrary UUID text entry (no discoverability or permission proof), a public catalog (metadata disclosure), unbounded list/count (resource cost), automatically connecting the first row (wrong library risk), and returning a separate client or raw credential (bypasses the admitted identity lifetime).

## Tasks and verification

| Wave | Task / coverage | Files | Approximate diff | Targeted check |
| --- | --- | --- | --- | --- |
| 1 | Actual server spec regressions WD01–WD04, WD06 | New `Server/WorkspaceService/test/library-discovery.test.ts`; existing owned PG fixture helpers only if required | 220 lines | New discovery tests fail for missing GET behavior |
| 1 | Swift wire/admission spec regressions WD03–WD06 | New `Modules/SkriptumWorkspaceClient/Tests/SkriptumWorkspaceClientTests/LibraryDiscoveryTests.swift` | 180 lines | Missing API/contract and stale-response failures |
| 2 | Authenticated server reads WD01–WD04 | `Server/WorkspaceService/src/workspace-store.ts`, `http-gateway.ts`; dedicated `library-discovery.ts` if reusable query parsing warrants it | 200 lines | Actual discovery HTTP/PG tests |
| 2 | Typed identity reads WD03–WD05 | New module metadata type file; `WorkspaceIdentityClient.swift`; existing strict wire parser only if needed | 160 lines | Focused Swift discovery tests |
| 3 | Real wire fixture and complete validation WD06 | Client owned signed verification fixture and its pinned server manifest; service verification runner registration | 100 lines | Signed issuer/PG/Swift fixture, service full checks, module full tests, app SDK build |

The service and module tasks touch disjoint files. Shared test helpers remain owned by one task at a time. Preserve existing assertions; fix implementation after genuine red evidence. Any schema/index change needs an explicit plan amendment and migration/readiness compatibility tests first.

Verification must include an account with many space/page grants in a candidate library and prove discovery issues only the exact root-membership query, returns at most 8 rows, and never loads those child memberships. Test both authorization after a held library lock and timeout cleanup using the existing per-statement/lock contract. Pool acquisition and overall request deadlines remain separate service hardening work; they are not inferred from these SQL settings.

Method tooling: `pulse status` confirmed this repository has no active `.pulse/config.toml`. This plan follows the repository's existing reviewed-document workflow; it does not claim a Pulse board claim or mechanical P1–P6 validation. No Pulse setup or repository-method migration is introduced by this feature.

## Activation path and subsequent work

Server GET routes → authenticated transaction → locked root authorization → bounded metadata reply → admitted Swift identity actor. This contract stage does not yet add an app picker or synchronize local documents. The subsequent native stage must use real current credential-admission tickets, per-window/facade generations, role readback before binding, owned-locator persistence and stale-selection cancellation. A retained listing is not ongoing permission authority. Encryption-key provisioning, scoped shares, collaborative merge and worker execution remain required parts of the original goal.

## Stop conditions and limitations

No default account/operator, guessed production URL, test credential in app configuration, real-Apple claim from a signed local fixture, or manual weakening of role checks. Retain actual failure logs. Native QA, production HTTPS/operator/vault, Apple provisioning and physical-device tests remain separate gates. No unrelated collaboration vendor experiments are touched.

## Change log

- 2026-10-09: Source inspection established that `WorkspaceWire.swift` currently rejects arrays. The client task explicitly adds bounded opt-in arrays; existing parsing defaults stay unchanged. Implement metadata types and their internal wire decoder in `WorkspaceLibraryMetadata.swift`, and the actor methods in `WorkspaceIdentityClient.swift`. Add a narrow `IdentitySessionState.validateRead` helper in `WorkspaceIdentitySessionState.swift` that checks the existing private exact snapshot match and known monotonic expiry without revealing a credential or changing admission.
- 2026-10-09: The frozen server WD02 fixture in `test/library-discovery.test.ts` initially set only `disabled_at` and failed the existing accounts constraint before reaching its HTTP assertion. The requirement now states canonical tombstone fixture fields. The exact SQL setup diff was shown to the user before editing: add `disabled_reason='account-delete'` and `tombstoned_at=clock_timestamp()`. Keep all 401 assertions and schema unchanged; retain the 6-pass/1-fixture-failure evidence.

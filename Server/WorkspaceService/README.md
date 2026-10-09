# Scriptum WorkspaceService — relational/ACL wave

Node24 + TypeScript7, exact-pinned node-postgres8.23.1. `package-lock.json` retains registry URLs/integrities; dependencies installed with lifecycle scripts disabled. A bounded built-in HTTP gateway is implemented and verified on loopback. Public deployment, provider calls, vault secrets, issuer enrollment and native wiring remain absent.

## What is implemented

Executable PostgreSQL18 migration creates relational accounts, opaque server sessions, libraries, Spaces, encrypted pages/revision history, hierarchical memberships, schedules/runs/reservations/results and content-free audit. Compound library/Space/page keys isolate identical page UUIDs in different libraries. Revision CAS and prior encrypted-source history write share one transaction. Ciphertext/nonce/digest/key-reference columns enforce bounded envelope structure; real encryption/decryption/key rotation belongs to an eventual verified vault adapter. Verification bytes are explicitly synthetic ciphertext, not evidence of production cryptography.

`WorkspaceStore` identity comes only from hashed-token `server_sessions` lookup with expiry/revocation. It never accepts a claimed account/role for authorization. Fresh session admission is rechecked after library lock waits. Every library-scoped operation and membership mutation uses the same library row lock and fresh inherited rank. Owner/editor/viewer ranks propagate through parent ceilings; explicit child overrides only restrict effective access. UUIDs normalize before override matching, so uppercase aliases cannot bypass lower overrides. Native untrusted Automerge ingress remains absent.

`migrate` validates exact schema migration checksum and does not erase/replace existing tables. An immutable server-managed key registry and shared nonce ledger protect current pages, archived envelopes and encrypted results. Library-bound registered references cannot be supplied from another library. Historical content retention never frees nonce claims. Migration2 seeds existing envelopes and fails atomically for conflicting usage. Same checked-out pg client owns BEGIN/COMMIT/ROLLBACK. No retries conceal conflicts or external side effects. This code currently serializes library operations conservatively; a measured concurrency optimization is a following change.

## Commands and safety

```sh
npm ci --ignore-scripts
npm run build
npm run test:unit
```

Migration needs explicit `SCRIPTUM_DATABASE_URL` and `SCRIPTUM_DATABASE_SCHEMA`. Configure private credentials outside source control; commands/logs do not print connection URLs/tokens. Production gateway/restricted database-role configuration is not provisioned here.

Real integration tests require a dedicated loopback PostgreSQL18 database URL in `SCRIPTUM_VERIFICATION_DATABASE_URL` plus `SCRIPTUM_ALLOW_VERIFICATION_SCHEMA=YES`, then `npm run test:integration`. Each run creates a random `wsverify_<UUID>` schema; cleanup drops only that owned schema. It never erases a database, public schema, existing user's tables or unrelated container/volume. Missing opt-in/infrastructure deliberately FAILS, never produces a mock/skipped database PASS.

Ten executed integration tests exercise idempotent migration/restart, actual encrypted-page/history persistence and conflict rollback, inherited/lowered roles including uppercase IDs, same-page UUID tenant isolation, forged/expired/revoked sessions, a real blocked writer after committed revocation, delegation ceilings, historical nonce immutability, exact result/run target binding, and nonempty legacy nonce migration success/conflict rollback. Concurrent test observes a real PostgreSQL lock wait before revoker commits, rather than treating a delay as evidence.

## Executed evidence and infrastructure boundary

Actual Node24.19.0/npm11.17.0 typecheck passed. Five validation/wire/test-boundary unit tests passed (`work/workspace-validation-{red,green}.log`); dependency install and typecheck logs are in root work. These are NOT PostgreSQL tests.

Read-only Docker preflight found client29.6.2/colima with no daemon socket; no VM/container/volume was started or modified. Parent subsequently provisioned an owned loopback PostgreSQL18.6 from official source (SHA256 `555610c24d53e4316da5b7d3fc25c279d96856d5e0e23ee308c328c5fa881d9f`) under root work. Private verification credentials are outside this repository and were passed only through process environment, never printed.

Actual PostgreSQL RED: preserved old migration/service plus permanent nonce regression ran7tests,6passed and A→B→A failed because old code accepted nonce reuse (`work/workspace-postgres-nonce-red.log`). Fixed service/migrations ran **10real PostgreSQL tests, all PASS, no skipped tests** (`work/workspace-postgres-green.log`). Seeded migration proof includes populated legacy pages/history: success preserves exact ciphertext/revisions; conflicting history rolls back schema/version/content. Unique owned schemas and session-level advisory locks were cleaned; parent owns daemon shutdown. The earlier no-infrastructure command remains historical evidence, not current blocker. Typecheck and5unit tests also pass.

## HTTP gateway and bootstrap

`npm run start` requires explicit private `SCRIPTUM_DATABASE_URL` and `SCRIPTUM_DATABASE_SCHEMA`, checks migration readiness, and defaults to127.0.0.1:8787. Non-loopback binding requires explicit `SCRIPTUM_ALLOW_EXTERNAL_BIND=YES`; setting it is deployment configuration, not evidence of production TLS or authorization. No bootstrap registers a user/session/key, no login/dev token fallback exists, and CORS/OPTIONS are not enabled.

Routes support health/readiness, owner library/Space creation, registered-key encrypted page create/read/strong quoted If-Match CAS, owner membership grant/revoke at library/Space/page scope, and authenticated logout revocation. Opaque Bearer session admission is database-backed and checked again inside operations. Caller account/role authority is never accepted from body fields. Private missing/forbidden errors share404; SQL errors return controlled codes without query/constraint/token/content details.

Strict wire parser rejects duplicate/escaped duplicate JSON keys, trailing data, invalid UTF8/surrogates, unknown DTO fields, noncanonical base64, weak/list/unquoted If-Match, query/percent paths and unsupported media. Header8KiB, body3MiB, JSONdepth16/nodes512, connection64 and default8in-flight bounds apply. Body5s, pool acquisition≤5s, SQL5s, headers5s/request/socket10s deadlines are real underlying timers. A concurrency slot remains held until BOTH handler work and response completion/close settle, including aborted clients; no Promise.race hides continuing queued SQL. Default tests use smaller owned body bounds for controlled413 verification.

Actual HTTP+PostgreSQL proof: **9tests PASS, no skips** in `work/workspace-http-green.log`; retained SQL suite10PASS and unit5PASS. Initial actual501 listener/PG fixture gave7contract failures (`workspace-http-red.log`). Reviewed abort regression reproduced2pending handlers under limit1 (`workspace-http-concurrency-red.log`); fixed owned delayed-handler test proves no second handler admitted until actual work settles. Test boundaries reject non-loopback URLs/absent opt-in before connecting and require actual PostgreSQL18 before creating any fixture schema. All loopback servers and owned schemas/locks were cleaned; parent owns daemon shutdown. These are local gateway proofs, not production/native/session-enrollment proofs.

## Following required gates

Independent review of frozen SQL/service; verified issuer/session enrollment and production HTTP deployment; runtime DB privilege/RLS defense policy; vault/region/private source encryption proof; media/hierarchy/recovery sync; scheduling actor-to-database contracts and worker leases/budgets; atomic proposal acceptance receipt/document update; real sharing clients/offline execution, revocation/cancellation races; TLS/rate limits/backups/deployment readback. Schema rows alone are not a running scheduler or production collaboration.

Primary references: [PostgreSQL18 isolation](https://www.postgresql.org/docs/18/transaction-iso.html), [PostgreSQL18 row security](https://www.postgresql.org/docs/18/ddl-rowsecurity.html), [node-postgres transactions](https://node-postgres.com/features/transactions). Explicit application ACL/locks are implemented; DB RLS is not claimed.

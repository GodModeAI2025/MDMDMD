# Scriptum WorkspaceService — relational/ACL wave

Node24 + TypeScript7, exact-pinned node-postgres8.23.1. `package-lock.json` retains registry URLs/integrities; dependencies installed with lifecycle scripts disabled. No HTTP listener, public deployment, provider call, vault secret, issuer enrollment or native wiring exists in this wave.

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

Actual Node24.19.0/npm11.17.0 typecheck passed. Two validation unit tests RED→GREEN passed (`work/workspace-validation-{red,green}.log`); dependency install and typecheck logs are in root work. These are NOT PostgreSQL tests.

Read-only Docker preflight found client29.6.2/colima with no daemon socket; no VM/container/volume was started or modified. Parent subsequently provisioned an owned loopback PostgreSQL18.6 from official source (SHA256 `555610c24d53e4316da5b7d3fc25c279d96856d5e0e23ee308c328c5fa881d9f`) under root work. Private verification credentials are outside this repository and were passed only through process environment, never printed.

Actual PostgreSQL RED: preserved old migration/service plus permanent nonce regression ran7tests,6passed and A→B→A failed because old code accepted nonce reuse (`work/workspace-postgres-nonce-red.log`). Fixed service/migrations ran **10real PostgreSQL tests, all PASS, no skipped tests** (`work/workspace-postgres-green.log`). Seeded migration proof includes populated legacy pages/history: success preserves exact ciphertext/revisions; conflicting history rolls back schema/version/content. Unique owned schemas and session-level advisory locks were cleaned; parent owns daemon shutdown. The earlier no-infrastructure command remains historical evidence, not current blocker. Typecheck and2unit tests also pass.

## Following required gates

Independent review of frozen SQL/service; authenticated HTTP API/verified issuer and session lifecycle; runtime DB privilege/RLS defense policy; vault/region/private source encryption proof; media/hierarchy/recovery sync; scheduling actor-to-database contracts and worker leases/budgets; atomic proposal acceptance receipt/document update; real sharing clients/offline execution, revocation/cancellation races; TLS/rate limits/backups/deployment readback. Schema rows alone are not a running scheduler or production collaboration.

Primary references: [PostgreSQL18 isolation](https://www.postgresql.org/docs/18/transaction-iso.html), [PostgreSQL18 row security](https://www.postgresql.org/docs/18/ddl-rowsecurity.html), [node-postgres transactions](https://node-postgres.com/features/transactions). Explicit application ACL/locks are implemented; DB RLS is not claimed.

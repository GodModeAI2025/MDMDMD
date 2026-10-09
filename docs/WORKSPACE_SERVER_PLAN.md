# Workspace service — first real relational/ACL wave

## Concrete boundary

Node24/TypeScript + PostgreSQL18 + exact-pinned node-postgres (`pg`). Implement executable relational migration, opaque server-session admission, inherited ACL and revision-bound encrypted-page read/write transactions. No native changes or untrusted Automerge ingress. No HTTP deployment/worker/issuer/vault provisioning is claimed by this wave.

Read-only preflight2026-10-09: local Node24.19.0/npm11.17.0; Docker client29.6.2 uses colima context, server unavailable because ~/.colima/default/docker.sock does not exist. Do not start a global VM/daemon or modify unrelated containers. Real database integration is blocked until an eligible engine is available. Integration command must fail plainly when no explicit verification database URL is supplied, never substitute SQLite/mock/file storage or count a skipped suite as PASS. Only an owned PostgreSQL18 verification container/database may be provisioned under later available-engine authorization, localhost binding and isolated ephemeral volume.

## Files and storage contracts

`Server/WorkspaceService/sql/001_workspace.sql`: accounts; server_sessions; libraries; spaces; encrypted pages; scoped memberships; schedules; runs; account budget reservations; proposals/read-only summaries; audit; schema migrations. Account/library/Space/page compound keys prevent same page UUID collision across libraries. Opaque session lookup is based on a hashed random token inserted only by a future verified identity gateway. Requests never provide role/account identity. No live issuer/token/credential is invented.

Page content is opaque authenticated encryption ciphertext plus nonce/key-reference/envelope version and exact-byte source digest. Production keys are vault-managed and not stored in this DB or request body. This wave can verify synthetic ciphertext relational persistence; it cannot claim real production source encryption/key rotation until the vault/provider adapter is implemented. No source plaintext column and no provider secrets/logging.

`src/transaction.ts`: same checked-out pg client BEGIN/COMMIT/ROLLBACK; no automatic retries in this wave; serialization/deadlock failures roll back explicitly. A later reviewed retry policy may apply only before an external side effect. This wave has no external side effects. Use per-library row lock shared by every read-authorized mutation and membership revocation, then fresh session/ACL checks in that transaction. A queued writer after committed revocation denies; a writer that commits before revocation is a valid preceding operation. Do not claim retroactive revocation or rely on a stale cached grant.

`src/workspace-store.ts`: session-backed create/read/write/membership revoke/grant operations, parameterized SQL, expected page revision/CAS, immutable namespaces. Identity comes only from current server_sessions row and expiry/revocation. Library owner implicit owner; others require library membership. Child Space/page explicit roles are upper-bound overrides: effective rank=min(parent effective role, explicit child override, applicable delegation ceilings). Child membership cannot restore access after library revocation or elevate a viewer to editor. Inherited effective owner/editor/viewer is computed fresh; owner management never takes a role from payload. Delegation ceilings cannot exceed parent ceiling. Membership management validates target rank against current manager and parent ceiling; explicit lower override remains restrictive.

Relational schedule/run/reservation/result tables are bounded, linked by tenant scope and constraints. This first wave does not dispatch them; audited durable scheduler integration and server worker follow. Results discriminate proposal vs read-only summary; no arbitrary content becomes a document write. Atomic result acceptance receipt/document mutation remains an explicit following transaction gate.

## Permanent proof requirements

Real PostgreSQL integration fixtures in an explicitly opted-in dedicated verification database/schema: executable idempotent migration/restart, private source ciphertext persistence/revision conflict rollback, same page UUID two libraries isolation, owner/editor/viewer inherited rights, lower overrides and delegation ceiling rejection, forged body identity rejected by absent/expired/revoked sessions, and two-client revocation/write ordering. Use real SQL row locks and concurrent clients; no in-memory fake DB. Test cleanup only drops uniquely owned schemas created by this suite, with verification URL opt-in and advisory lock. Unknown/existing schema/database is never erased.

Unit-only tests may verify strict UUID/envelope/ACL rank input checks, but are reported separately from PostgreSQL evidence. Exact dependency lock/integrities, source hashes, executed commands and infrastructure errors saved in the service README/evidence. Parent independently reviews the frozen implementation before native wiring.

## Primary implementation references

[PostgreSQL18 transaction isolation](https://www.postgresql.org/docs/18/transaction-iso.html), [row-security context](https://www.postgresql.org/docs/18/ddl-rowsecurity.html), [node-postgres same-client transaction contract](https://node-postgres.com/features/transactions), [Node24 official release](https://nodejs.org/en/blog/release/v24.19.0). This service uses explicit transactional ACL checks and locking; it does not claim DB RLS enforcement unless actually installed and verified.

## Following gates

Actual PostgreSQL integration when infrastructure is available; HTTP authenticated API and verified issuer/audience/session lifecycle; restricted runtime DB credentials; production vault/key rotation/region policy; object/media storage; authorized scheduling database/state-machine worker and billing; role inheritance across sharing device clients; cancellation/idempotency/fenced leases; proposal acceptance receipt; TLS/rate limits/backups/migrations and deployment readback; offline-device/server execution proof. Existing ChatGPT/PCC native sessions do not imply unattended server authorization. No new billable hosting/public binding authorized by this document.

## Reviewed nonce/target ownership amendment (before implementation)

Current-row nonce uniqueness cannot protect retired encrypted revisions: A→B→A must reject historical nonce reuse even after history retention removes content. Add an immutable server-managed key registry with library ownership and a shared nonce-usage ledger keyed by key reference+nonce across page/results writes. Page/history/result rows reference registered keys belonging to their library. Only future verified vault enrollment (or explicit synthetic test SQL) registers keys; request payload cannot create aliases. Insert/update triggers reserve nonce identity before an encrypted write; ledger update/delete is rejected. Migration seeds from existing current/history/result envelopes, permits duplicate copies of the exact same archived envelope, but rejects conflicting same-key+nonce uses without modifying prior state. Source retention never frees nonce usage.

Real PostgreSQL regression first: create encrypted A, write B, attempt A's original nonce again; rejection must preserve exact B/current revision, archived A and audit counts. Registered key ownership denies using another library's key reference. Node typecheck/unit evidence is separate; actual RED/GREEN waits for parent's owned PostgreSQL18 runtime.

Also bind each run to its schedule's exact Space/page via compound foreign keys, and each result to that run's exact target. The verification suite holds a session-level advisory lock for its unique owned schema until cleanup; no claim of an unimplemented global lock. Transaction helper currently performs no automatic retries; serialization/deadlock failures are explicit rollback failures. Remove any promise that this wave already implements retry policy.


Executed backend gate2026-10-09: parent provisioned private owned PostgreSQL18.6 official-source runtime after Docker preflight failure. Old nonce baseline:7realSQLtests,6PASS plus expected historical nonce regressionFAIL. Fixed migrations/service:10realSQLtests PASS (no skips), including actual blocked transaction revocation, populated legacy nonce seeding and conflicting migration rollback. Typecheck+2unit tests PASS. All unique owned schemas/locks cleaned; no database/daemon/user container deletion. Official source SHA retained in README. Public HTTP/deployment/provider/worker/native/vault gates remain open.

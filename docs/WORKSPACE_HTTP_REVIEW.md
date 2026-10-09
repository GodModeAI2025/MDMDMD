# Frozen HTTP gateway independent review

Verdict: PASS implemented owned-localhost business API subset; no remaining confirmed blocker found in reviewed corrections. No production authentication/TLS/vault/worker/native/deployment claim.

Start/end hash6acf5ae21bd76f677a288f9363b68ec15e9ccd0832465b8eb09c5c3cfa9eb1cc (sorted service-relative files path+NUL+bytes+NUL excluding node_modules/EVIDENCE.json), frozen builder confirmation. Independent typecheck exit0; units5/5, SQL10/10, real HTTP9/9 all exit0/no skipped tests. Evidence work/workspace-http-independent-{typecheck,unit,sql,http}.log. Parent-owned private config read without URL print; authorized local connection escalation. Only test-owned random advisory-locked schemas/local gateways cleaned; no DB drop or parent daemon stop. Processes terminal, parent notified.

## Corrected findings

http-gateway active capacity now releases only once both response lifecycle and route Promise settle. Client abort cannot free still-running database handler capacity. Real owned delayed-store regression aborts first response, proves maximum handler1, second request503, and settles all handlers before cleanup. HTTP/SQL fixtures share protocol+loopback+explicit opt-in verifier and query PostgreSQL major18 before creating schema; absent/remote configuration fails closed. No unknown database contacted.

## Inspected source and executable proof

Raw authorization counts preserve duplicate evidence; one opaque Bearer token only. Gateway prevalidates current session; every store mutation/read reauthenticates/current transactional ACL, so no supplied caller account/actor/issuer/role can bypass DB identity. Membership targetAccount is managed subject, not caller. Unknown/duplicate JSON keys, escaped aliases, unpaired surrogates, malformed UTF8, noncanonical base64 and unknown DTO fields reject. Query/fragment/percent path aliases reject; UUIDs normalize; strong quoted If-Match drives expected-revision CAS. Bounded3MiB body,8KiB header, depth/node counts, timeout/socket/connection/request and in-flight caps present. Oversized chunk input returns413 without buffering beyond limit and closes connection.

Private resource missing/forbidden both404; absent/expired/revoked auth401. Error mapper returns only controlled codes/status and no SQL/constraint/query/token/source details. Readiness is status-only boolean and health opaque; no permissive CORS. Logout revokes current session in DB and subsequent request fails. Real HTTP tests verify encrypted GET/CAS conflicts, historical nonce rollback, lower viewer denial, strict wire boundaries, body oversize, controlled SQL errors, logout/expiry, abort concurrency and owner create/Space/page/grant/revoke routes. Prior ten real SQL tests remain green, retaining history/nonce/tenant/revocation/migration invariants.

Bootstrap requires explicit database URL/schema and successful readiness, bounded8pool/5sconnection acquisition, defaults127.0.0.1:8787; external bind requires explicit opt-in. It creates no fallback identity/key, does not auto-migrate schema and logs no URL/details. Startup catch emits generic unavailable. Shutdown closes local connections and waits for pool clients; no production deployment tested. HTTP handlers require caller supply already authenticated ciphertext envelopes; registered key references/nonce history remain enforced by SQL, not native secrets.

## Explicit limits

No verified identity issuer/audience/session enrollment, production TLS/AEAD/vault/rotation/region policy, restricted runtime DB credentials/RLS, worker/billing/cancellation/fences, native clients, media, atomic proposal-acceptance receipt, deployment/backups/rate-limit/account-retention proof. Sessions/envelopes in fixtures are synthetic and HTTP local only. Full R08/R09/product remain open. This is ordinary business/data-integrity authorization review, not broad security/compliance certification. No source edits/commits or external probes.

# Identity advanced fault verification

Parent independent verification:53aggregate tests passed,0failures,0skips, exit0 (`work/workspace-identity-advanced-independent.log`). Manifest recomputed exactly as listed in EVIDENCE.json and matched `9d29b2e291a381109c90039ce48a46d490d03b65d9f01e6885069abf6bf81df2`. Parent separately compared every production src/SQL file to b4035c2 and found no differences. Scoped review PASS for these owned fault scenarios; physical database-daemon crash, production vault/deployment and live Apple/native delivery remain outside this proof.

Baseline: reviewed/committed b4035c2,48tests. This wave changes permanent owned test fixtures/tests only unless a concrete failure requires a reviewed production fix.

1. A child process performs real signed/code HTTPS enrollment and actual AES-GCM vault retention, then signals a content-free IPC barrier. Parent kills only that owned child; restart reads durable SQL compensation reference and encrypted vault, rejects challenge replay, performs real issuer revocation, and creates no session/account.
2. The child connects to parent PostgreSQL through a private owned loopback TCP proxy. After vault-retention barrier parent closes only that proxy/client sockets, simulating complete database transport loss for that child; parent PG and other users stay untouched. Finalization and failure cleanup cannot connect. Restart through direct PG connection recovers provisioning reference and revokes grant. No database or shared daemon stop.
3. Separate owned HTTPS token/revoke endpoints delay beyond their actual5s deadline. Verify socket cancellation/one request/no retry and no issuer-selected URLs; no production issuer calls.
4. Two independent workers share real PostgreSQL and one delayed revocation job. Observe persisted lease/attempt and overlapping cycles; one provider call, stale-fence update rejected, bounded non-overlap and durable completion.
5. Stop a worker during actual slow in-flight HTTPS revocation. Signal cancellation joins actual handler, clears lease, retains uncertain state/cost-free grant reference for bounded retry, and no later cycle/request runs.

All cases own random advisory-locked schemas, loopback listeners, child PIDs/proxy sockets and private fixture vault directories. Credentials/key material are passed only through private environment/IPC and never logged/committed. Explicit outer deadlines kill only owned child/process group and always close resources. Parent owns shared PostgreSQL shutdown. Production source stays unchanged until failure is demonstrated and coordinated.

## Executed evidence

Final mandatory aggregate53tests PASS/no skips/typecheck PASS (`work/workspace-identity-advanced-all.log`), including all reviewed48baseline cases plus5newpermanent advanced cases. Standalone advanced output `work/workspace-identity-advanced.log` proves actual owned child SIGKILL, complete database transport loss for that child through an owned TCP proxy, durable restart compensation, two independent overlapping worker instances with one persisted lease/attempt/provider request, real slow-worker shutdown/socket cancellation, and separate token/revoke5s deadlines.

Observed final advanced durations: process kill recovery~0.526s; database-transport loss/recovery~0.493s; overlapping workers~0.404s; in-flight shutdown~0.221s; two consecutive token/revoke deadlines~10.174s. Assertions bound each5s network deadline to4.5–6.5s, shutdown<1.5s, child barriers10s, exit2s and proxy/worker probes2s. These are local observed operational bounds, not a production latency guarantee.

Initial DB-loss fixture failure was a proxy URL closure incorrectly forwarding to its own listener; correcting a separate child URL fixed the fixture. No production source defect/fix was required. A test-only sanitized Error.code TypeScript cast was corrected before the final aggregate. Child IPC carries only ephemeral fixture keys/proofs privately; output carries only barrier/outcome codes. All child PIDs, proxies/sockets, HTTPS listeners, owned schemas/advisory locks and fixture vault folders are cleaned. Parent PostgreSQL was never stopped or changed by this wave.

Production src/sql remains byte-identical to committed b4035c2. This proves full connection loss for the owned enrollment process; it does NOT claim a physical PostgreSQL-daemon crash/restart or live Apple/provider behavior. Apple/device/native/deployment/restricted-role/vault and scheduling gates remain open separately.

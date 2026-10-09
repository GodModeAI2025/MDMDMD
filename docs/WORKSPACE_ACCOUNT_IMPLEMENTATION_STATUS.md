# Native workspace account implementation checkpoint

The scoped restore/login/logout kernel and production adapters are implemented and independently reviewed. They are not activated in the account UI and do not complete R08/R09 or the full product.

The process-shared synchronous gate serializes generation/denial/session CAS and real Security operations. A bounded no-follow private denial ledger blocks cold restoration after failed removal; stale saves/removals preserve newer credentials. Service/context ownership rejects conflicting roots. Coordinator attempts preserve known unrelated accounts, consume exact attempt IDs on all terminal paths, reject stale GET/logout replies, perform exact local cleanup after cancelled saves, retain failed-denial retry information, and latch explicit proof cancellation before a late Apple prompt. Production adapters use actual identity/admission clients and mandatory registry invalidation; no default endpoint, account enumeration or automatic document upload exists.

Current frozen-source evidence:

- Entire root package: 201 Swift Testing tests plus 24 XCTest tests = 225, exit 0 (`work/workspace-account-root-final.log`).
- Full regenerated iOS 27 simulator App SDK build: exit 0, BUILD SUCCEEDED (`work/workspace-account-app-final-sdk.log`). Compilation only; no signing/upload claim.
- Full module: 29 tests, exit 0 (`work/workspace-admission-full-regression-final.log`). Its initial empty-bootstrap-JSON failure was traced to asynchronous publication of a visible partial fixture file and corrected with private pending-file plus atomic rename; assertions and production behavior were unchanged. The first failure is preserved.
- Immutable signed HTTPS issuer/HTTP/PostgreSQL identity fixture: 20 assertions PASS (`work/workspace-admission-real-identity-regression.log`). Synthetic owned issuer; production Apple identity/vault remains separate.
- Simulator: original 16 Security protection assertions and 10 new admission assertions PASS; see `qa-workspace-credential-admission/README.md`. Independent repeat awaits the recorded Xcode MCP approval.
- Native canonical Foundation-root repository traversal: see `qa-workspace-container-roots/README.md`; simulator host paths do not prove physical /var/mobile aliases.

Fresh scoped review and security audit PASS are retained in WORKSPACE_ACCOUNT_FINAL_REVIEW.md and WORKSPACE_ACCOUNT_FINAL_AUDIT.md. SCA/OSV coverage was unavailable offline; reports state that limitation. No confirmed Critical/High or concrete blocker remains in their inspected component snapshot.

Remaining activation work includes native account settings/logout/deletion confirmation and fresh receipt flow, real scene/Apple authorization composition, trusted system-container root handling and physical path/locked-device evidence, coordinator end-to-end HTTPS/service proof, production deployment/operator/TLS/vault and actual Apple configuration. Realtime editing, deployed scheduling and remaining provider/device requirements retain their original scope. TestFlight Build 2 predates this code; no new upload is claimed.

# Fresh account deletion kernel checkpoint

The native coordinator and real identity adapter now implement the reviewed deletion contract. Fresh authorization is exact-account and separate from existing sessions; its credential/receipt stays in memory and is not saved to Keychain. Wrong-account authorization targets only its newly issued session for cleanup. Matching account windows and connection handles are fenced and durable accountDeletion denial committed before the destructive operation. Local documents, histories, attachments and owned/shared libraries are retained by the contract.

A shared synchronous one-way start control is claimed inside the identity actor before receipt consumption, local invalidation and request initiation. Cancellation winning before that local authorization claim sends no DELETE and preserves the receipt/admission. A winning start cannot be undone or represented as confirmed remote deletion. The start is not proof of TCP delivery. Real actor/owned HTTP regression demonstrated the previous failure (8 issues) then the correction; the scheduling checkpoint is internal immutable DEBUG+SWIFT_PACKAGE only, with public initializer nil and no shipping App hook.

Cleanup UUID, reservation UUID and generation are checked after every awaited retry stage; old retries cannot clear a newer deletion. Pre-fence targeted-session cleanup is reported separately as confirmed/unknown. Local retries never resend DELETE. Post-fence cancellation/receipt failures always target-clean the fresh issued session, preserve local denial, and report uncertainty honestly.

Final evidence on frozen corrected source:

- Root package: 202 Swift Testing + 36 XCTest = 238 tests, exit 0 (`work/workspace-deletion-final-root.log`).
- Full iOS 27 App SDK build: exit 0, BUILD SUCCEEDED (`work/workspace-deletion-final-app-sdk.log`).
- Full client module: 32 tests, exit 0; prior 29 assertions retained (`work/workspace-deletion-start-full-module.log`).
- Immutable signed HTTPS issuer/HTTP/PostgreSQL identity fixture: 20 assertions PASS (`work/workspace-deletion-start-real-server.log`).
- Fresh independent scoped review/security audit PASS: retained final reports. Coordinator fake scheduling tests do not substitute for actual module actor/HTTP proof, native UI or production Apple identity.

Native confirmation/account settings, actual scene authorization composition, configured coordinator end-to-end service proof, deployment/operator/TLS/vault, physical Apple/container/locked-device and ambiguous remote-result reconciliation remain activation gates. UI/composition plan is separately reviewed, not implemented by this checkpoint. Internal TestFlight Build 2 still predates this source; no new upload or installed-device claim.

# Native library picker — implementation status

The account inspector now exposes explicit selection of existing remote libraries through its actual runtime. Opening requires an active account and exact operator acknowledgement. The production driver retains actual restored/enrolled credentials and admission tickets privately, validates them before/after metadata requests, and holds the shared admission gate through the trusted synchronous binding CAS. Kernel validation inside that commit never reenters the gate.

The picker replaces its eight-row page and retains at most sixteen previous cursors. Selection requires a currently displayed UUID and fresh exact metadata readback. It persists only the actual owned binding; documents/history remain unchanged, and the UI explicitly distinguishes association from synchronization or encryption-key provisioning.

## Tested boundaries

- Six new admission cases plus ten existing cases passed. Real context/private ledger and synthetic Security isolate matching credentials, denied/replaced scopes and both racing commit orders; they do not prove actual device Keychain behavior.
- Thirteen actual kernel/registry/repository picker tests passed, including two added account-isolation regressions and two consumer/cold-adoption cases. Fake discovery drivers prove scheduling and repository CAS, not production identity authority.
- Two additional runtime boundary cases passed: unconfigured selection invokes no authentication/write and stale facades are rejected.
- Complete app checks passed 212 Swift Testing and 58 XCTest tests, 270 total, exit 0 (`native-picker-root-full.log`).
- Complete client fixture passed all 44 tests, exit 0, including real owned HTTP/PostgreSQL verification (`native-picker-module-owned-phased-full.log`). Its initial cold compile exceeded the old combined 30-second timer before tests began. Build now has a separate bounded 60-second phase; test execution retains the original 30-second limit. No assertion or runtime test deadline was relaxed.
- Full iOS 27 app SDK build succeeded (`native-picker-consumer-app-sdk.log`). Independent foundation and activation reviews passed; the final harness/manifest supplement verified unchanged production hashes and all complete results.

The reviewed fixes preserve a different account's same-locator association and active same-account siblings, retain real cold metadata handles with exact verified-scope adoption, and bind every selection sheet to its own synchronously installed consumer UUID. Late old-sheet cancellation cannot affect a replacement request.

Frozen-fixture corrections were explicitly shown before editing and recorded in the plan: async semaphore helper with unchanged timeout, redundant existing-directory creation removal and FIFO driver activation order. Other existing assertions remain intact. Async app-test barriers still rely on scoped process supervision rather than an intrinsic fixture timeout; their green result is not a production deadline proof.

## Required evidence still open

Actual configured production Runtime/Keychain/signed-service/repository bridging and native picker interaction remain to be proved. Earlier signed discovery evidence covers the wire contract, not this activation bridge. No default endpoint/operator/account, raw credential getter or fake configured shipping path was introduced.

First remote library creation, narrow scoped-resource sharing, encryption-key provisioning, document synchronization, simultaneous collaborative editing, deployed scheduled execution, actual provider/PCC/commercial ChatGPT/device activation and updated internal TestFlight delivery remain part of the original application goal. An association-only UI does not complete those requirements.

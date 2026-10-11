# Durable scheduled content permission and legacy pause

2026-10-11. Source base51588fe plus this patch; verification.json binds final source/test/build hashes.

New native activation now records contentPermissionVersion1 in the same atomic scheduling transaction that activates the task. The optional field decodes older records as unapproved; it does not synthesize permission for missing metadata. Current approved records retain activation after restart. Pause/cancel clear permission, while revision creates an unapproved replacement requiring fresh review.

After validating actual owned-library/account scope, LocalScheduleSession startup atomically pauses legacy active tasks without current permission, increments their generation and fences pending runs using the existing cancellation rules. Prompt, source permissions, schedule, counters and saved outputs are retained. Known unsent reservations release; potentially dispatched/running/uncertain costs remain uncertain. The refreshed migrated ledger is then imported into the shared owner budget. An unchanged second load performs no further migration write. The background discovery route does not select legacy unapproved tasks for new execution, and ScheduledAIExecutor rejects absent permission before access/inference even if reached directly.

Four new regressions (five parameter cases) cover atomic persistence failure/rollback and reopen, queued versus dispatched cost handling, idempotence, approved restart and pause clearing, a direct legacy native-executor denial before an intentionally failing access check, and an actual legacy tasks-v1.json native-session migration followed by fresh review/approval/reopen. Controlled native transport fixtures explicitly simulate current permission; generic scheduler fixtures remain separate from human authority. The stored stamp is a scoped implementation record, not independent proof that a person operated the dialog.

Full suite627 Swift Testing headline/four opt-in skips plus58XCTest passes. Unsigned Debug Simulator and iOS Release builds pass. No live provider, OS background timing, physical-device migration, power-loss/process race or human UI approval is inferred from these scoped tests. All R01-R15 requirements and signed current-source TestFlight delivery remain open.

## Fresh native access check

The device-interaction delegate verified source51588fe and saved a fresh [readiness receipt](../qa-content-permission-native-20261011/native-readiness.json). Xcode shows Archives; the old approval dialog is absent in that capture. MCP still reports permission disabled and server not running, with no exposed native/device tools. No permission/server/bridge/install/inference action occurred. Consent dialogs and migration are therefore not natively accepted by this update.

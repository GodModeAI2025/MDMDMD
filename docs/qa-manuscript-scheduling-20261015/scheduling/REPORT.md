# Final scheduled transmission admission

A deterministic reproduction of the real `LocalScheduleDispatcher` → `ScheduledAIExecutor` path found that the second asynchronous provider-access check ran after dispatch/start and all freshness checks. Persisted Pause/Cancel, trashed source, expired quote and UTC month rollover during that check still started the mock provider with private source content. The baseline executable links the pre-change production Swift modules; its source and five JSON observations are retained here. This does not call a remote AI service.

The executor now requires a final `beforeSending` callback after access/request checks and immediately before starting the stream. The dispatcher performs current source, lifecycle/generation, lease, quote and month checks and its durable dispatch/start inside that callback. Invalidated calls remain unsent. Existing durable local rejection still releases the owner reservation even when local reservation persistence failed; a matching already-cancelled run with no provider request reference and either absent or released local reservation can release its still-unsent owner reservation too. After durable dispatch, uncertainty and no-blind-retry behavior are unchanged.

Verification:
- `baseline.jsonl`: all five invalidated scenarios sent once; cancellation and pause had already persisted before stream startup.
- `final.jsonl`: same five scenarios now send zero times, store no output and do not receive a provider request reference.
- `focused.log`: six parameter cases, including ordinary success, passed. The test checks both ledgers, restart persistence and exact original manuscript UTF-8.
- `scheduling-final.log`: 75 workspace-model definitions (two optional price-document/live-network checks skipped) and 39 scheduling definitions passed. This is 112 executed definitions, not 114 actual executions; the new single definition has six cases. Existing reservation-persistence fault, ambiguous dispatched run, access revocation, Swift cancellation and no-retry checks passed.
- `reservation-final.log`: after review found cancellation during the owner-reserve await can precede local reservation creation, two additional deterministic cases now cover that window. All eight parameter cases plus the existing unsent-reservation write-failure and uncertain-dispatch write-failure regressions pass (three definitions, 0.099 seconds). This is the last test run against final sources; the broader run above predates this narrow cleanup follow-up.
- Final standalone compile/run exited zero before that cleanup follow-up. `SOURCE_HASHES.json` binds production and test files. `git diff --check` passed.

No device/simulator, actual provider billing, live catalog/network or portal operations were performed in this audit. The parent is responsible for SDK builds and delivery.

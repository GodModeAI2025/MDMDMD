# iOS 27 asynchronous background request submission

2026-10-10. The installed iPhoneOS 27 SDK deprecates the synchronous BGTaskScheduler submission method because it cannot report every error condition. Its replacement can complete on an arbitrary queue after an arbitrary delay and must not be called from the main thread or a performance-critical context. Source: BackgroundTasks.framework/Headers/BGTaskScheduler.h in the installed Xcode iPhoneOS.sdk, lines 106–145. This change follows that actual SDK declaration.

## Implementation

- Request construction and the new `try await submitTaskRequest(_:)` call run in an `@concurrent` helper. Requests are not constructed on MainActor and passed across isolation boundaries. Cancellation also uses the helper.
- `BackgroundRequestQueue` serializes submission and cancellation through their asynchronous completions. A delayed old submission cannot complete after and replace a newer cancellation or replacement. Its operation lifetime belongs to the queue, not the calling scene or task.
- The coordinator changes its confirmed submitted date and error only for the current request generation. Enqueuing a newer operation invalidates an earlier confirmation. A superseded empty-plan cancellation also cannot remove a newer retry floor.
- A BGProcessingTask expiry handler is installed before waiting for fallback submission confirmation. It cancels execution, completes the expired system task once and releases the current-run slot. The operation retains its run context, still submits the fallback, then checks cancellation before any provider execution. Its later completion cannot clear a newer run. This is source-level lifecycle logic, not a verified OS-delivered expiry event.
- Existing activation consent, ownership/source checks, budgets, provider binding and no-fallback policies remain unchanged. An earliest begin date is an OS request, not a timed-execution promise.

## Verification

Full test suite passes: 432 Swift Testing functions and 58 XCTest cases, three optional skips. New controlled-delay tests exercise submission → cancellation → replacement ordering and a canceled caller whose owned submission still completes before cancellation. These tests cover the shared queue, not BGTaskScheduler itself or the entire application coordinator.

Xcode MCP Build 751 passes with no errors. An initial build failed because app sources flatten local modules; conditional module import plus XcodeGen inclusion corrected this. The initial failed receipt is retained in work/shared-catalog-qa/async-background-submit-build.json.

Optimized unsigned iOS Release 1.0.0 (3) passes. Executable SHA-256: `ad1118b1b95926b26822417ae5eba502a2a46bcf2072b40e0c39a2b8038315ed`. BGTask submission deprecation warnings are absent; the pre-existing native text binding Sendable warning remains. This is not a signed archive or TestFlight delivery.

Native simulator smoke confirms app startup, manager response, inactive draft creation and cancellation using the real UI. No real provider request or background activation was performed. The 283-file Swift/config manifest includes the new queue, its tests and the native coordinator and is unchanged before the session ends. See REPORT.md and screenshots.

## Remaining evidence

Actual OS submission acceptance, system background launch, delivery of expiry, execution on a physical device and scheduling latency are unproven. The SDK permits arbitrarily delayed confirmation: a provider run waits for fallback confirmation and aborts if its system execution window has expired. No guarantee of prompt background execution is claimed. Profile/capability provisioning and a newly signed TestFlight upload remain separate gates.

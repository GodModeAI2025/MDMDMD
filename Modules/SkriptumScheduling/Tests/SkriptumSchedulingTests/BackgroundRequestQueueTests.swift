import Testing
@testable import SkriptumScheduling

private actor DelayedScheduler {
    var events: [String] = []
    var pending: String?
    var callerCancellationReachedOperation = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func submitDelayed() async {
        events.append("old-start")
        await withCheckedContinuation { continuation = $0; started?.resume(); started = nil }
        callerCancellationReachedOperation = Task.isCancelled
        pending = "old"; events.append("old-confirmed")
    }
    func waitStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
    func cancel() { pending = nil; events.append("cancel") }
    func submitNew() { pending = "new"; events.append("new-confirmed") }
}

@Test func backgroundQueueOrdersDelayedSubmitCancelAndReplacement() async {
    let queue = BackgroundRequestQueue(), scheduler = DelayedScheduler()
    let (_, first) = await queue.enqueue { await scheduler.submitDelayed() }
    await scheduler.waitStarted()
    let (_, cancel) = await queue.enqueue { await scheduler.cancel() }
    let (_, replacement) = await queue.enqueue { await scheduler.submitNew() }
    #expect(await scheduler.pending == nil)
    await scheduler.release()
    await first.value; await cancel.value; await replacement.value
    #expect(await scheduler.events == ["old-start", "old-confirmed", "cancel", "new-confirmed"])
    #expect(await scheduler.pending == "new")
}

@Test func backgroundQueueOwnsSubmissionDespiteCallerCancellation() async {
    let queue = BackgroundRequestQueue(), scheduler = DelayedScheduler()
    let caller = Task { await queue.perform { await scheduler.submitDelayed() } }
    await scheduler.waitStarted(); caller.cancel()
    let (_, cancel) = await queue.enqueue { await scheduler.cancel() }
    await scheduler.release(); await caller.value; await cancel.value
    #expect(await scheduler.callerCancellationReachedOperation == false)
    #expect(await scheduler.events == ["old-start", "old-confirmed", "cancel"])
    #expect(await scheduler.pending == nil)
}

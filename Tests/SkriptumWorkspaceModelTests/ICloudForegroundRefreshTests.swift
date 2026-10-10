import Foundation
import Testing
@testable import SkriptumWorkspaceModel

@MainActor struct ICloudForegroundRefreshTests {
    @MainActor private final class Pauses {
        var waiting: [CheckedContinuation<Void, Never>] = []
        func pause(_ duration: Duration) async throws {
            #expect(duration == .milliseconds(600))
            await withCheckedContinuation { waiting.append($0) }
            try Task.checkCancellation()
        }
        func resume() { waiting.removeFirst().resume() }
    }
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<2000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Expected controlled asynchronous checkpoint not reached")
    }
    @Test func idleBackgroundAndBurstEditsDoNotStartUnboundedRefreshes() async {
        let pauses = Pauses(); var calls = 0
        let worker = ICloudForegroundRefresh(pause: { try await pauses.pause($0) }) { calls += 1 }
        worker.request(); await Task.yield()
        #expect(pauses.waiting.isEmpty && calls == 0)
        worker.setActive(true)
        await until { pauses.waiting.count == 1 }
        for _ in 0..<100 { worker.request() }
        pauses.resume()
        await until { pauses.waiting.count == 1 }
        #expect(calls == 0)
        pauses.resume()
        await until { calls == 1 }
        for _ in 0..<10 { await Task.yield() }
        #expect(pauses.waiting.isEmpty && calls == 1)
        worker.setActive(false); worker.request()
        #expect(!worker.isActive && pauses.waiting.isEmpty)
    }
    @Test func inFlightWriteFinishesBeforeCoalescedSuccessorBegins() async {
        let pauses = Pauses(); var calls = 0
        var operation: CheckedContinuation<Void, Never>?
        let worker = ICloudForegroundRefresh(pause: { try await pauses.pause($0) }) {
            calls += 1
            if calls == 1 { await withCheckedContinuation { operation = $0 } }
        }
        worker.setActive(true)
        await until { pauses.waiting.count == 1 }; pauses.resume()
        await until { operation != nil }
        for _ in 0..<100 { worker.request() }
        for _ in 0..<10 { await Task.yield() }
        #expect(calls == 1 && pauses.waiting.isEmpty)
        operation?.resume(); operation = nil
        await until { pauses.waiting.count == 1 }; pauses.resume()
        await until { calls == 2 }
        #expect(pauses.waiting.isEmpty)
        worker.setActive(false)
    }
    @Test func rapidSceneReturnCannotOverlapUncooperativeInFlightOperation() async {
        let pauses = Pauses(); var calls = 0
        var operation: CheckedContinuation<Void, Never>?
        let worker = ICloudForegroundRefresh(pause: { try await pauses.pause($0) }) {
            calls += 1
            if calls == 1 { await withCheckedContinuation { operation = $0 } }
        }
        worker.setActive(true)
        await until { pauses.waiting.count == 1 }; pauses.resume()
        await until { operation != nil }
        worker.setActive(false); worker.setActive(true)
        for _ in 0..<10 { await Task.yield() }
        #expect(calls == 1 && pauses.waiting.isEmpty)
        operation?.resume(); operation = nil
        await until { pauses.waiting.count == 1 }
        #expect(calls == 1)
        pauses.resume(); await until { calls == 2 }
        worker.setActive(false)
    }
    @Test func oldCanceledCompletionCannotRetireReactivatedWorker() async {
        let pauses = Pauses(); var calls = 0
        let worker = ICloudForegroundRefresh(pause: { try await pauses.pause($0) }) { calls += 1 }
        worker.setActive(true)
        await until { pauses.waiting.count == 1 }
        worker.setActive(false); worker.setActive(true)
        for _ in 0..<10 { await Task.yield() }
        #expect(pauses.waiting.count == 1 && calls == 0)
        // The replacement must wait for the canceled worker to actually finish.
        pauses.resume()
        await until { pauses.waiting.count == 1 }
        #expect(calls == 0 && worker.isActive)
        worker.request(); pauses.resume()
        await until { pauses.waiting.count == 1 }
        #expect(calls == 0)
        pauses.resume(); await until { calls == 1 }
        worker.setActive(false)
    }
}

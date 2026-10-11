import Foundation
import Testing
@testable import SkriptumScheduling

struct ContentPermissionMigrationTests {
    @Test(arguments: [false, true])
    func legacyMigrationIsAtomicAndRetainsUncertainCosts(dispatched: Bool) async throws {
        let memory = MemoryPersistence(), store = try SchedulingStore(persistence: memory)
        let (task, grant) = try StoreTests().fixture(), now = Date(timeIntervalSince1970: 100)
        try await store.add(task, expectedVersion: 0)
        try await store.activate(taskID: task.id, grant: grant, now: now, expectedVersion: 1)
        let ids = try await store.enqueueDue(now: now, expectedVersion: 2), id = try #require(ids.first)
        let lease = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(30))
        try await store.claim(runID: id, lease: lease, now: now, expectedVersion: 3)
        try await store.authorize(runID: id, fence: lease.fence, grant: grant, now: now, expectedVersion: 4)
        let quote = BudgetQuote(currency: "USD", maximumMicros: 80, inputTokens: 10, outputTokens: 10,
            version: "v", expiresAt: now.addingTimeInterval(100))
        try await store.reserve(runID: id, fence: lease.fence, quote: quote, expectedQuoteVersion: "v", now: now, expectedVersion: 5)
        if dispatched {
            try await store.dispatch(runID: id, fence: lease.fence, requestReference: "legacy-sent", grant: grant,
                expectedQuoteVersion: "v", now: now, expectedVersion: 6)
        }
        let before = await store.snapshot(), bytes = try memory.read()
        memory.fail = true
        do { _ = try await store.pauseTasksWithoutContentPermission(expectedVersion: before.version); Issue.record("Failed migration committed") } catch {}
        #expect(await store.snapshot() == before)
        #expect(try memory.read() == bytes)
        memory.fail = false
        #expect(try await store.pauseTasksWithoutContentPermission(expectedVersion: before.version) == [task.id])
        let after = await store.snapshot()
        #expect(after.tasks[task.id]?.lifecycle == .paused && after.tasks[task.id]?.generation == 2)
        #expect(after.tasks[task.id]?.prompt == task.prompt && after.tasks[task.id]?.allowedBlockIDs == task.allowedBlockIDs)
        #expect(after.runs[id]?.state == .cancelled)
        #expect(after.ledger.reservations[id]?.state == (dispatched ? .uncertain : .released))
        #expect(after.ledger.reservations[id]?.quote.maximumMicros == 80)
        let reopened = try SchedulingStore(persistence: memory)
        #expect(await reopened.snapshot() == after)
        #expect(try await reopened.pauseTasksWithoutContentPermission(expectedVersion: after.version).isEmpty)
        #expect(await reopened.snapshot() == after)
    }

    @Test func approvedPermissionPersistsAndPauseClearsIt() async throws {
        let memory = MemoryPersistence(), store = try SchedulingStore(persistence: memory)
        let (task, grant) = try StoreTests().fixture(), now = Date(timeIntervalSince1970: 50)
        try await store.add(task, expectedVersion: 0)
        try await store.activate(taskID: task.id, contentPermissionVersion: ScheduledTask.currentContentPermissionVersion,
            grant: grant, now: now, expectedVersion: 1)
        let reopened = try SchedulingStore(persistence: memory)
        #expect(await reopened.snapshot().tasks[task.id]?.contentPermissionVersion == 1)
        #expect(try await reopened.pauseTasksWithoutContentPermission(expectedVersion: 2).isEmpty)
        try await reopened.pause(taskID: task.id, grant: grant, now: now, expectedGeneration: 1, expectedVersion: 2)
        #expect(await reopened.snapshot().tasks[task.id]?.contentPermissionVersion == nil)
    }
}

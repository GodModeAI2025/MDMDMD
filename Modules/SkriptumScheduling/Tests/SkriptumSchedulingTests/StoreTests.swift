import Foundation
import Testing

@testable import SkriptumScheduling

final class MemoryPersistence: SchedulingPersistence, @unchecked Sendable {
  let lock = NSLock()
  var data: Data?
  var fail = false
  func read() throws -> Data? { lock.withLock { data } }
  func write(_ value: Data) throws {
    try lock.withLock {
      if fail { throw CocoaError(.fileWriteNoPermission) }
      data = value
    }
  }
}
struct StoreTests {
  func fixture() throws -> (ScheduledTask, ExecutionGrant) {
    let scope = SchedulingScope(accountID: UUID(), libraryID: UUID(), spaceID: UUID())
    let page = UUID()
    let block = UUID()
    let task = try ScheduledTask(
      scope: scope, pageID: page, allowedBlockIDs: [block], prompt: "Proofread",
      providerBindingID: UUID(), rule: .oneShot(Date(timeIntervalSince1970: 100)),
      budget: .init(
        currency: "USD", perRunMicros: 100, monthlyMicros: 200, inputTokens: 100, outputTokens: 100),
      createdAt: Date(timeIntervalSince1970: 0))
    let grant = ExecutionGrant(
      scope: scope, taskID: task.id, generation: 1, accountMonthlyMicros: 200,
      expiresAt: Date(timeIntervalSince1970: 1000), role: .owner, readablePageIDs: [page],
      readableBlockIDs: [block])
    return (task, grant)
  }
  @Test func persistenceCASRestartAndWriteFailureAreAtomic() async throws {
    let memory = MemoryPersistence()
    let store = try SchedulingStore(persistence: memory)
    let (task, grant) = try fixture()
    try await store.add(task, expectedVersion: 0)
    await #expect(throws: SchedulingError.staleVersion) {
      try await store.add(task, expectedVersion: 0)
    }
    try await store.activate(
      taskID: task.id, grant: grant, now: Date(timeIntervalSince1970: 50), expectedVersion: 1)
    let before = await store.snapshot()
    let bytes = try memory.read()
    memory.fail = true
    do {
      try await store.cancel(taskID: task.id, expectedGeneration: 1, expectedVersion: 2)
      Issue.record("Write failure accepted")
    } catch {}
    #expect(await store.snapshot() == before)
    #expect(try memory.read() == bytes)
    memory.fail = false
    let restarted = try SchedulingStore(persistence: memory)
    #expect(await restarted.snapshot() == before)
  }
  @Test func occurrenceFencingCancellationAndLateCompletion() async throws {
    let store = try SchedulingStore(persistence: MemoryPersistence())
    let (task, grant) = try fixture()
    let now = Date(timeIntervalSince1970: 100)
    try await store.add(task, expectedVersion: 0)
    try await store.activate(taskID: task.id, grant: grant, now: now, expectedVersion: 1)
    let ids = try await store.enqueueDue(now: now, expectedVersion: 2)
    #expect(ids.count == 1)
    #expect(try await store.enqueueDue(now: now, expectedVersion: 3).isEmpty)
    let old = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(10))
    try await store.claim(runID: ids[0], lease: old, now: now, expectedVersion: 4)
    let fresh = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(30))
    try await store.claim(
      runID: ids[0], lease: fresh, now: now.addingTimeInterval(11), expectedVersion: 5)
    do {
      try await store.authorize(
        runID: ids[0], fence: old.fence, grant: grant, now: now.addingTimeInterval(12),
        expectedVersion: 6)
      Issue.record("Old fence accepted")
    } catch SchedulingError.expiredLease {}
    try await store.authorize(
      runID: ids[0], fence: fresh.fence, grant: grant, now: now.addingTimeInterval(12),
      expectedVersion: 6)
    try await store.cancel(taskID: task.id, expectedGeneration: 1, expectedVersion: 7)
    let state = await store.snapshot()
    #expect(state.tasks[task.id]?.lifecycle == .cancelled)
    #expect(state.runs[ids[0]]?.state == .cancelled)
    do {
      try await store.complete(
        runID: ids[0], fence: fresh.fence, grant: grant, now: now.addingTimeInterval(13),
        expectedVersion: 8)
      Issue.record("Late completion accepted")
    } catch {}
    #expect(await store.snapshot() == state)
  }
  @Test func unknownSchemaAndOversizedFilesRejected() throws {
    let memory = MemoryPersistence()
    memory.data = Data(
      #"{"schemaVersion":2,"version":0,"tasks":{},"runs":{},"ledger":{"reservations":{}},"proposals":{}}"#
        .utf8)
    #expect(throws: (any Error).self) { try SchedulingStore(persistence: memory) }
    memory.data = Data(repeating: 32, count: 32 * 1024 * 1024 + 1)
    #expect(throws: SchedulingError.persistenceTooLarge) {
      try SchedulingStore(persistence: memory)
    }
  }
  @Test func grantsRejectOtherLibraryAndViewerWithoutInventedAuthority() throws {
    let (task, grant) = try fixture()
    try grant.admit(task, now: Date(timeIntervalSince1970: 50))
    let other = ExecutionGrant(
      scope: SchedulingScope(
        accountID: task.scope.accountID, libraryID: UUID(), spaceID: task.scope.spaceID),
      taskID: task.id, generation: 1, accountMonthlyMicros: 200, expiresAt: grant.expiresAt,
      role: .owner, readablePageIDs: [task.pageID], readableBlockIDs: task.allowedBlockIDs)
    #expect(throws: SchedulingError.denied) {
      try other.admit(task, now: Date(timeIntervalSince1970: 50))
    }
    let viewer = ExecutionGrant(
      scope: task.scope, taskID: task.id, generation: 1, accountMonthlyMicros: 200,
      expiresAt: grant.expiresAt, role: .viewer, readablePageIDs: [task.pageID],
      readableBlockIDs: task.allowedBlockIDs)
    #expect(throws: SchedulingError.denied) {
      try viewer.admit(task, now: Date(timeIntervalSince1970: 50))
    }
  }
}

extension StoreTests {
  @Test func realFileRestartSymlinkGuardAndUnknownSchema() async throws {
    let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent(
      UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("state.json")
    let persistence = try FileSchedulingPersistence(url: file)
    let store = try SchedulingStore(persistence: persistence)
    let (task, _) = try fixture()
    try await store.add(task, expectedVersion: 0)
    let reloaded = try SchedulingStore(persistence: persistence)
    #expect(await reloaded.snapshot() == store.snapshot())
    let link = root.appendingPathComponent("link.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    #expect(throws: SchedulingError.unsafeFile) {
      try SchedulingStore(persistence: FileSchedulingPersistence(url: link))
    }
    var bad = await store.snapshot()
    bad.schemaVersion = 2
    try JSONEncoder().encode(bad).write(to: file)
    #expect(throws: SchedulingError.unsupportedSchema) {
      try SchedulingStore(persistence: persistence)
    }
  }
  @Test func dispatchCrashBecomesUncertainAndNeverSilentlyRetries() async throws {
    let memory = MemoryPersistence()
    let store = try SchedulingStore(persistence: memory)
    let (task, grant) = try fixture()
    let now = Date(timeIntervalSince1970: 100)
    try await store.add(task, expectedVersion: 0)
    try await store.activate(taskID: task.id, grant: grant, now: now, expectedVersion: 1)
    let ids = try await store.enqueueDue(now: now, expectedVersion: 2)
    let id = ids[0]
    let lease = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(10))
    try await store.claim(runID: id, lease: lease, now: now, expectedVersion: 3)
    try await store.authorize(
      runID: id, fence: lease.fence, grant: grant, now: now, expectedVersion: 4)
    let quote = BudgetQuote(
      currency: "USD", maximumMicros: 80, inputTokens: 10, outputTokens: 10, version: "v",
      expiresAt: now.addingTimeInterval(100))
    try await store.reserve(
      runID: id, fence: lease.fence, quote: quote, expectedQuoteVersion: "v", now: now,
      expectedVersion: 5)
    try await store.dispatch(
      runID: id, fence: lease.fence, requestReference: "opaque-run", grant: grant,
      expectedQuoteVersion: "v", now: now, expectedVersion: 6)
    let restarted = try SchedulingStore(persistence: memory)
    try await restarted.recoverExpired(now: now.addingTimeInterval(11), expectedVersion: 7)
    let uncertain = await restarted.snapshot()
    #expect(uncertain.runs[id]?.state == .executionUncertain)
    #expect(uncertain.ledger.reservations[id]?.state == .uncertain)
    await #expect(throws: SchedulingError.invalidTransition) {
      try await restarted.claim(
        runID: id, lease: RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(40)),
        now: now.addingTimeInterval(12), expectedVersion: 8)
    }
    try await restarted.cancel(taskID: task.id, expectedGeneration: 1, expectedVersion: 8)
    try await restarted.cancel(taskID: task.id, expectedGeneration: 1, expectedVersion: 9)
    #expect(await restarted.snapshot().ledger.reservations[id]?.state == .uncertain)
  }
}

extension StoreTests {
  @Test func creationCannotBypassActivationGrant() async throws {
    let store = try SchedulingStore(persistence: MemoryPersistence())
    var (task, _) = try fixture()
    task.lifecycle = .active
    await #expect(throws: SchedulingError.invalidTransition) {
      try await store.add(task, expectedVersion: 0)
    }
    #expect(await store.snapshot().tasks.isEmpty)
  }
  @Test func releasedReservationCannotResumeAndDispatchRechecksGrant() async throws {
    let store = try SchedulingStore(persistence: MemoryPersistence())
    let (task, _) = try fixture()
    let now = Date(timeIntervalSince1970: 100)
    let grant = ExecutionGrant(
      scope: task.scope, taskID: task.id, generation: 1, accountMonthlyMicros: 200,
      expiresAt: now.addingTimeInterval(1), role: .owner, readablePageIDs: [task.pageID],
      readableBlockIDs: task.allowedBlockIDs)
    try await store.add(task, expectedVersion: 0)
    try await store.activate(taskID: task.id, grant: grant, now: now, expectedVersion: 1)
    let ids = try await store.enqueueDue(now: now, expectedVersion: 2)
    let id = ids[0]
    let lease = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(10))
    try await store.claim(runID: id, lease: lease, now: now, expectedVersion: 3)
    try await store.authorize(
      runID: id, fence: lease.fence, grant: grant, now: now, expectedVersion: 4)
    let quote = BudgetQuote(
      currency: "USD", maximumMicros: 80, inputTokens: 10, outputTokens: 10, version: "v",
      expiresAt: now.addingTimeInterval(100))
    try await store.reserve(
      runID: id, fence: lease.fence, quote: quote, expectedQuoteVersion: "v", now: now,
      expectedVersion: 5)
    await #expect(throws: SchedulingError.denied) {
      try await store.dispatch(
        runID: id, fence: lease.fence, requestReference: "opaque", grant: grant,
        expectedQuoteVersion: "v", now: now.addingTimeInterval(2), expectedVersion: 6)
    }
    var invalid = await store.snapshot()
    try invalid.ledger.release(runID: id)
    #expect(throws: SchedulingError.invalidValue) { try invalid.validate() }
  }
}

extension StoreTests {
  @Test func ancestorLinkAndRealWriteFailurePreservePriorDiskState() async throws {
    let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent(
      UUID().uuidString)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
      try? FileManager.default.removeItem(at: root)
    }
    let file = root.appendingPathComponent("state.json")
    let store = try SchedulingStore(persistence: FileSchedulingPersistence(url: file))
    let (task, _) = try fixture()
    try await store.add(task, expectedVersion: 0)
    let before = await store.snapshot()
    let bytes = try Data(contentsOf: file)
    let parentLink = root.appendingPathComponent("linked-parent")
    try FileManager.default.createSymbolicLink(at: parentLink, withDestinationURL: root)
    #expect(throws: SchedulingError.unsafeFile) {
      try SchedulingStore(
        persistence: FileSchedulingPersistence(url: parentLink.appendingPathComponent("state.json"))
      )
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
    let (second, _) = try fixture()
    do {
      try await store.add(second, expectedVersion: 1)
      Issue.record("Permission denied write succeeded")
    } catch {}
    #expect(await store.snapshot() == before)
    #expect(try Data(contentsOf: file) == bytes)
  }
  @Test func concurrentFinalOwnerBudgetReservationHasSingleWinner() async throws {
    let store = try SchedulingStore(persistence: MemoryPersistence())
    let (first, _) = try fixture()
    let now = Date(timeIntervalSince1970: 100)
    let otherScope = SchedulingScope(
      accountID: first.scope.accountID, libraryID: first.scope.libraryID, spaceID: UUID())
    let second = try ScheduledTask(
      scope: otherScope, pageID: UUID(), allowedBlockIDs: [UUID()], prompt: "Second",
      providerBindingID: UUID(), rule: first.rule, budget: first.budget, createdAt: first.createdAt)
    for task in [first, second] {
      try await store.add(task, expectedVersion: store.snapshot().version)
      let grant = ExecutionGrant(
        scope: task.scope, taskID: task.id, generation: 1, accountMonthlyMicros: 100,
        expiresAt: Date(timeIntervalSince1970: 1000), role: .owner, readablePageIDs: [task.pageID],
        readableBlockIDs: task.allowedBlockIDs)
      try await store.activate(
        taskID: task.id, grant: grant, now: now, expectedVersion: store.snapshot().version)
    }
    let ids = try await store.enqueueDue(now: now, expectedVersion: store.snapshot().version)
    var leases: [UUID: RunLease] = [:]
    for id in ids {
      let state = await store.snapshot()
      let task = state.tasks[state.runs[id]!.occurrence.taskID]!
      let lease = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(30))
      leases[id] = lease
      try await store.claim(runID: id, lease: lease, now: now, expectedVersion: state.version)
      let grant = ExecutionGrant(
        scope: task.scope, taskID: task.id, generation: 1, accountMonthlyMicros: 100,
        expiresAt: Date(timeIntervalSince1970: 1000), role: .owner, readablePageIDs: [task.pageID],
        readableBlockIDs: task.allowedBlockIDs)
      try await store.authorize(
        runID: id, fence: lease.fence, grant: grant, now: now,
        expectedVersion: store.snapshot().version)
    }
    let version = await store.snapshot().version
    let quote = BudgetQuote(
      currency: "USD", maximumMicros: 80, inputTokens: 10, outputTokens: 10, version: "v",
      expiresAt: Date(timeIntervalSince1970: 1000))
    let fixedLeases = leases
    let winners = await withTaskGroup(of: Bool.self) { group in
      for id in ids {
        group.addTask {
          do {
            try await store.reserve(
              runID: id, fence: fixedLeases[id]!.fence, quote: quote, expectedQuoteVersion: "v",
              now: now, expectedVersion: version)
            return true
          } catch { return false }
        }
      }
      var count = 0
      for await success in group { if success { count += 1 } }
      return count
    }
    #expect(winners == 1)
    let state = await store.snapshot()
    let loser = ids.first { state.ledger.reservations[$0] == nil }!
    await #expect(throws: SchedulingError.budgetDenied) {
      try await store.reserve(
        runID: loser, fence: leases[loser]!.fence, quote: quote, expectedQuoteVersion: "v",
        now: now, expectedVersion: state.version)
    }
  }
}

extension StoreTests {
  @Test func settledUncertainCostSurvivesCancellationAndRestart() async throws {
    let memory = MemoryPersistence()
    let store = try SchedulingStore(persistence: memory)
    let (task, grant) = try fixture()
    let now = Date(timeIntervalSince1970: 100)
    try await store.add(task, expectedVersion: 0)
    try await store.activate(taskID: task.id, grant: grant, now: now, expectedVersion: 1)
    let ids = try await store.enqueueDue(now: now, expectedVersion: 2)
    let id = ids[0]
    let lease = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(10))
    try await store.claim(runID: id, lease: lease, now: now, expectedVersion: 3)
    try await store.authorize(
      runID: id, fence: lease.fence, grant: grant, now: now, expectedVersion: 4)
    let quote = BudgetQuote(
      currency: "USD", maximumMicros: 80, inputTokens: 10, outputTokens: 10,
      version: "v", expiresAt: now.addingTimeInterval(100))
    try await store.reserve(
      runID: id, fence: lease.fence, quote: quote, expectedQuoteVersion: "v", now: now,
      expectedVersion: 5)
    try await store.dispatch(
      runID: id, fence: lease.fence, requestReference: "opaque", grant: grant,
      expectedQuoteVersion: "v", now: now, expectedVersion: 6)
    try await store.recoverExpired(now: now.addingTimeInterval(11), expectedVersion: 7)
    try await store.settle(runID: id, actualMicros: 70, expectedVersion: 8)
    let ledger = await store.snapshot().ledger
    try await store.cancel(taskID: task.id, expectedGeneration: 1, expectedVersion: 9)
    let restarted = try SchedulingStore(persistence: memory)
    let state = await restarted.snapshot()
    #expect(state.tasks[task.id]?.lifecycle == .cancelled)
    #expect(state.runs[id]?.state == .cancelled)
    #expect(state.ledger == ledger)
    #expect(state.ledger.reservations[id]?.actualMicros == 70)
  }
  @Test func reclaimedLeaseRejectsReusedFenceWithoutChangingState() async throws {
    let memory = MemoryPersistence()
    let store = try SchedulingStore(persistence: memory)
    let (task, grant) = try fixture()
    let now = Date(timeIntervalSince1970: 100)
    try await store.add(task, expectedVersion: 0)
    try await store.activate(taskID: task.id, grant: grant, now: now, expectedVersion: 1)
    let ids = try await store.enqueueDue(now: now, expectedVersion: 2)
    let id = ids[0]
    let original = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(10))
    try await store.claim(runID: id, lease: original, now: now, expectedVersion: 3)
    let before = await store.snapshot()
    let bytes = try memory.read()
    let reused = RunLease(
      workerID: UUID(), fence: original.fence, expiresAt: now.addingTimeInterval(30))
    await #expect(throws: SchedulingError.invalidTransition) {
      try await store.claim(
        runID: id, lease: reused, now: now.addingTimeInterval(11), expectedVersion: 4)
    }
    #expect(await store.snapshot() == before)
    #expect(try memory.read() == bytes)
    let distinct = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(30))
    try await store.claim(
      runID: id, lease: distinct, now: now.addingTimeInterval(11), expectedVersion: 4)
    #expect(await store.snapshot().runs[id]?.lease == distinct)
  }
}

extension StoreTests {
  @Test func allPriorLeaseFencesRemainRejectedAfterRestart() async throws {
    let memory = MemoryPersistence()
    let store = try SchedulingStore(persistence: memory)
    let (task, grant) = try fixture()
    let now = Date(timeIntervalSince1970: 100)
    try await store.add(task, expectedVersion: 0)
    try await store.activate(taskID: task.id, grant: grant, now: now, expectedVersion: 1)
    let ids = try await store.enqueueDue(now: now, expectedVersion: 2)
    let id = ids[0]
    let first = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(10))
    try await store.claim(runID: id, lease: first, now: now, expectedVersion: 3)
    let second = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(20))
    try await store.claim(
      runID: id, lease: second, now: now.addingTimeInterval(11), expectedVersion: 4)
    let restarted = try SchedulingStore(persistence: memory)
    let before = await restarted.snapshot()
    let bytes = try memory.read()
    var malformed = before
    malformed.runs[id]?.usedFences = []
    #expect(throws: SchedulingError.invalidValue) { try malformed.validate() }
    let reusedFirst = RunLease(
      workerID: UUID(), fence: first.fence, expiresAt: now.addingTimeInterval(40))
    await #expect(throws: SchedulingError.invalidTransition) {
      try await restarted.claim(
        runID: id, lease: reusedFirst, now: now.addingTimeInterval(21), expectedVersion: 5)
    }
    #expect(await restarted.snapshot() == before)
    #expect(try memory.read() == bytes)
    await #expect(throws: SchedulingError.expiredLease) {
      try await restarted.authorize(
        runID: id, fence: first.fence, grant: grant, now: now.addingTimeInterval(21),
        expectedVersion: 5)
    }
    let third = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(40))
    try await restarted.claim(
      runID: id, lease: third, now: now.addingTimeInterval(21), expectedVersion: 5)
    #expect(await restarted.snapshot().runs[id]?.lease == third)
  }
}

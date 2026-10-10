import Foundation
import Testing

@testable import SkriptumScheduling

struct LifecycleTests {
  let dates = ISO8601DateFormatter()
  func grant(_ task: ScheduledTask, until: Date = .distantFuture) -> ExecutionGrant {
    ExecutionGrant(
      scope: task.scope, taskID: task.id, generation: task.generation, accountMonthlyMicros: 200,
      expiresAt: until, role: .owner, readablePageIDs: [task.pageID],
      readableBlockIDs: task.allowedBlockIDs)
  }
  @Test func monthlySkipsInvalidDayAndCatchupRespectsEndCount() async throws {
    let january = dates.date(from: "2026-01-31T10:00:00Z")!
    let rule = ScheduleRule.monthly(timeZone: "UTC", hour: 10, minute: 0, day: 31)
    #expect(try rule.next(after: january) == dates.date(from: "2026-03-31T10:00:00Z"))
    let (original, _) = try StoreTests().fixture()
    var task = original
    task.rule = .daily(timeZone: "UTC", hour: 0, minute: 0)
    task.scheduleEndUTC = Date(timeIntervalSince1970: 86400 * 4)
    task.maximumOccurrences = 3
    let memory = MemoryPersistence()
    let store = try SchedulingStore(persistence: memory)
    try await store.add(task, expectedVersion: 0)
    try await store.activate(
      taskID: task.id, grant: grant(task), now: task.createdAt, expectedVersion: 1)
    let ids = try await store.enqueueDue(
      now: Date(timeIntervalSince1970: 86400 * 10), expectedVersion: 2)
    let state = await store.snapshot()
    #expect(ids.count == 1 && state.tasks[task.id]?.occurrenceCount == 3)
    #expect(state.missedOccurrences.count == 1)
    #expect(state.missedOccurrences.values.first?.count == 2)
    #expect(state.runs[ids[0]]?.occurrence.scheduledUTC == Date(timeIntervalSince1970: 86400 * 2))
    let restarted = try SchedulingStore(persistence: memory)
    #expect(
      try await restarted.enqueueDue(
        now: Date(timeIntervalSince1970: 86400 * 20), expectedVersion: 3
      ).isEmpty)
  }
  @Test func pauseFencesOldGenerationAndResumeNeedsFreshGrant() async throws {
    let (task, _) = try StoreTests().fixture()
    let memory = MemoryPersistence()
    let store = try SchedulingStore(persistence: memory)
    let now = Date(timeIntervalSince1970: 100)
    try await store.add(task, expectedVersion: 0)
    try await store.activate(taskID: task.id, grant: grant(task), now: now, expectedVersion: 1)
    let ids = try await store.enqueueDue(now: now, expectedVersion: 2)
    let lease = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(60))
    try await store.claim(runID: ids[0], lease: lease, now: now, expectedVersion: 3)
    try await store.pause(
      taskID: task.id, grant: grant(task), now: now, expectedGeneration: 1, expectedVersion: 4)
    let paused = await store.snapshot().tasks[task.id]!
    #expect(paused.lifecycle == .paused && paused.generation == 2)
    await #expect(throws: SchedulingError.denied) {
      try await store.activate(taskID: task.id, grant: grant(task), now: now, expectedVersion: 5)
    }
    try await store.activate(taskID: task.id, grant: grant(paused), now: now, expectedVersion: 5)
    #expect(await store.snapshot().runs[ids[0]]?.state == .cancelled)
  }
  @Test func reviseRequiresActivationAndCancelledIntentIsTerminal() async throws {
    let (task, _) = try StoreTests().fixture()
    let store = try SchedulingStore(persistence: MemoryPersistence())
    let now = Date(timeIntervalSince1970: 100)
    try await store.add(task, expectedVersion: 0)
    try await store.activate(taskID: task.id, grant: grant(task), now: now, expectedVersion: 1)
    let intent = ScheduledIntent(
      rule: .daily(timeZone: "UTC", hour: 9, minute: 0), prompt: "New intent",
      allowedBlockIDs: task.allowedBlockIDs, providerBindingID: UUID(), action: .summary,
      budget: task.budget, scheduleEndUTC: nil, maximumOccurrences: 2)
    try await store.revise(
      taskID: task.id, intent: intent, grant: grant(task), now: now, expectedGeneration: 1,
      expectedVersion: 2)
    let revised = await store.snapshot().tasks[task.id]!
    #expect(
      revised.lifecycle == .awaitingActivation && revised.generation == 2
        && revised.scheduleAnchor == now)
    try await store.cancel(taskID: task.id, expectedGeneration: 2, expectedVersion: 3)
    await #expect(throws: SchedulingError.invalidTransition) {
      try await store.revise(
        taskID: task.id, intent: intent, grant: grant(revised), now: now, expectedGeneration: 3,
        expectedVersion: 4)
    }
  }
  @Test func legacySchemaOneMissingAdditionsLoadsWithoutRewriting() async throws {
    let memory = MemoryPersistence()
    let store = try SchedulingStore(persistence: memory)
    let (task, _) = try StoreTests().fixture()
    try await store.add(task, expectedVersion: 0)
    var object = try JSONSerialization.jsonObject(with: memory.read()!) as! [String: Any]
    object.removeValue(forKey: "summaries")
    object.removeValue(forKey: "missedOccurrences")
    var pairs = object["tasks"] as! [Any]
    var encoded = pairs[1] as! [String: Any]
    for key in ["scheduleAnchor", "occurrenceCount", "scheduleEndUTC", "maximumOccurrences"] {
      encoded.removeValue(forKey: key)
    }
    pairs[1] = encoded
    object["tasks"] = pairs
    let bytes = try JSONSerialization.data(withJSONObject: object)
    memory.data = bytes
    let loaded = try SchedulingStore(persistence: memory)
    #expect(await loaded.snapshot().tasks[task.id]?.scheduleAnchor == task.createdAt)
    #expect(try memory.read() == bytes)
  }
}

extension LifecycleTests {
  @Test func persistedSummaryIsReadOnlyAndRejectsExpiredPublication() async throws {
    let (original, _) = try StoreTests().fixture()
    var task = original
    task.action = .summary
    let memory = MemoryPersistence()
    let store = try SchedulingStore(persistence: memory)
    let now = Date(timeIntervalSince1970: 100)
    try await store.add(task, expectedVersion: 0)
    try await store.activate(taskID: task.id, grant: grant(task), now: now, expectedVersion: 1)
    let ids = try await store.enqueueDue(now: now, expectedVersion: 2)
    let id = ids[0]
    let lease = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(60))
    try await store.claim(runID: id, lease: lease, now: now, expectedVersion: 3)
    try await store.authorize(
      runID: id, fence: lease.fence, grant: grant(task), now: now, expectedVersion: 4)
    let quote = BudgetQuote(
      currency: "USD", maximumMicros: 80, inputTokens: 10, outputTokens: 10, version: "v",
      expiresAt: .distantFuture)
    try await store.reserve(
      runID: id, fence: lease.fence, quote: quote, expectedQuoteVersion: "v", now: now,
      expectedVersion: 5)
    try await store.dispatch(
      runID: id, fence: lease.fence, requestReference: "opaque", grant: grant(task),
      expectedQuoteVersion: "v", now: now, expectedVersion: 6)
    try await store.started(runID: id, fence: lease.fence, now: now, expectedVersion: 7)
    let revision = UUID()
    let summary = try ScheduledSummary(
      scope: task.scope, runID: id, pageID: task.pageID, baseRevision: revision,
      source: "exact\r\n", text: "Read-only summary 😀", providerID: "openai", modelID: "model",
      createdAt: now)
    await #expect(throws: SchedulingError.denied) {
      try await store.recordSummary(
        summary, fence: lease.fence, grant: grant(task, until: now), now: now, expectedVersion: 8)
    }
    try await store.recordSummary(
      summary, fence: lease.fence, grant: grant(task), now: now, expectedVersion: 8)
    let restarted = try SchedulingStore(persistence: memory)
    let state = await restarted.snapshot()
    #expect(state.summaries[summary.id] == summary && state.proposals.isEmpty)
    #expect(
      try summary.admit(
        scope: task.scope, pageID: task.pageID, revision: revision, source: "exact\r\n"))
    #expect(throws: SchedulingError.staleProposal) {
      try summary.admit(
        scope: task.scope, pageID: task.pageID, revision: revision, source: "exact\n")
    }
  }
}

extension LifecycleTests {
  @Test func historicalProposalSurvivesNarrowerRevisionAndRestart() async throws {
    let (task, _) = try StoreTests().fixture()
    let memory = MemoryPersistence()
    let store = try SchedulingStore(persistence: memory)
    let now = Date(timeIntervalSince1970: 100)
    try await store.add(task, expectedVersion: 0)
    try await store.activate(taskID: task.id, grant: grant(task), now: now, expectedVersion: 1)
    let ids = try await store.enqueueDue(now: now, expectedVersion: 2)
    let id = ids[0]
    let lease = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(60))
    try await store.claim(runID: id, lease: lease, now: now, expectedVersion: 3)
    try await store.authorize(
      runID: id, fence: lease.fence, grant: grant(task), now: now, expectedVersion: 4)
    let quote = BudgetQuote(
      currency: "USD", maximumMicros: 80, inputTokens: 10, outputTokens: 10, version: "v",
      expiresAt: .distantFuture)
    try await store.reserve(
      runID: id, fence: lease.fence, quote: quote, expectedQuoteVersion: "v", now: now,
      expectedVersion: 5)
    try await store.dispatch(
      runID: id, fence: lease.fence, requestReference: "opaque", grant: grant(task),
      expectedQuoteVersion: "v", now: now, expectedVersion: 6)
    try await store.started(runID: id, fence: lease.fence, now: now, expectedVersion: 7)
    let block = task.allowedBlockIDs.first!
    let proposal = try ScheduledProposal(
      scope: task.scope, runID: id, pageID: task.pageID, baseRevision: UUID(),
      allowedBlockIDs: [block], source: "old authorized source",
      replacementBlocks: [block: "proposal"])
    try await store.recordProposal(
      proposal, fence: lease.fence, grant: grant(task), now: now, expectedVersion: 8)
    let ledger = await store.snapshot().ledger
    let intent = ScheduledIntent(
      rule: .daily(timeZone: "UTC", hour: 9, minute: 0), prompt: "Narrower", allowedBlockIDs: [],
      providerBindingID: task.providerBindingID, action: .summary, budget: task.budget)
    try await store.revise(
      taskID: task.id, intent: intent, grant: grant(task), now: now.addingTimeInterval(1),
      expectedGeneration: 1, expectedVersion: 9)
    let restarted = try SchedulingStore(persistence: memory)
    let state = await restarted.snapshot()
    #expect(state.proposals[proposal.id] == proposal && state.ledger == ledger)
    #expect(state.runs[id]?.capturedAllowedBlockIDs == task.allowedBlockIDs)
    #expect(state.tasks[task.id]?.allowedBlockIDs.isEmpty == true)
    await #expect(throws: SchedulingError.invalidTransition) {
      try await restarted.recordProposal(
        proposal, fence: lease.fence, grant: grant(task), now: now, expectedVersion: 10)
    }
    #expect(throws: SchedulingError.staleProposal) {
      try proposal.admit(
        scope: task.scope, pageID: task.pageID, revision: proposal.baseRevision,
        source: "old authorized source", readableBlockIDs: [])
    }
  }
  @Test(arguments: [false, true]) func pausePreservesUncertainOrSettledDispatchCost(settled: Bool)
    async throws
  {
    let (task, _) = try StoreTests().fixture()
    let memory = MemoryPersistence()
    let store = try SchedulingStore(persistence: memory)
    let now = Date(timeIntervalSince1970: 100)
    try await store.add(task, expectedVersion: 0)
    try await store.activate(taskID: task.id, grant: grant(task), now: now, expectedVersion: 1)
    let ids = try await store.enqueueDue(now: now, expectedVersion: 2)
    let id = ids[0]
    let lease = RunLease(workerID: UUID(), expiresAt: now.addingTimeInterval(10))
    try await store.claim(runID: id, lease: lease, now: now, expectedVersion: 3)
    try await store.authorize(
      runID: id, fence: lease.fence, grant: grant(task), now: now, expectedVersion: 4)
    let quote = BudgetQuote(
      currency: "USD", maximumMicros: 80, inputTokens: 10, outputTokens: 10, version: "v",
      expiresAt: .distantFuture)
    try await store.reserve(
      runID: id, fence: lease.fence, quote: quote, expectedQuoteVersion: "v", now: now,
      expectedVersion: 5)
    try await store.dispatch(
      runID: id, fence: lease.fence, requestReference: "opaque", grant: grant(task),
      expectedQuoteVersion: "v", now: now, expectedVersion: 6)
    try await store.recoverExpired(now: now.addingTimeInterval(11), expectedVersion: 7)
    if settled { try await store.settle(runID: id, actualMicros: 70, expectedVersion: 8) }
    let before = await store.snapshot()
    let version = before.version
    try await store.pause(
      taskID: task.id, grant: grant(task), now: now.addingTimeInterval(12), expectedGeneration: 1,
      expectedVersion: version)
    let paused = await store.snapshot().tasks[task.id]!
    #expect(await store.snapshot().ledger == before.ledger)
    let intent = ScheduledIntent(
      rule: task.rule, prompt: "Paused edit", allowedBlockIDs: task.allowedBlockIDs,
      providerBindingID: task.providerBindingID, action: task.action, budget: task.budget)
    try await store.revise(
      taskID: task.id, intent: intent, grant: grant(paused), now: now.addingTimeInterval(13),
      expectedGeneration: 2, expectedVersion: version + 1)
    let restarted = try SchedulingStore(persistence: memory)
    #expect(await restarted.snapshot().tasks[task.id]?.lifecycle == .paused)
    #expect(await restarted.snapshot().ledger == before.ledger)
  }
  @Test func monthlyDSTEndBoundaryAndInvalidNewMetadata() async throws {
    let gap = ScheduleRule.monthly(timeZone: "Europe/Berlin", hour: 2, minute: 30, day: 29)
    #expect(
      try gap.next(after: dates.date(from: "2026-03-01T00:00:00Z")!)
        == dates.date(from: "2026-03-29T01:00:00Z"))
    let overlap = ScheduleRule.monthly(timeZone: "Europe/Berlin", hour: 2, minute: 30, day: 25)
    #expect(
      try overlap.next(after: dates.date(from: "2026-10-01T00:00:00Z")!)
        == dates.date(from: "2026-10-25T00:30:00Z"))
    let (original, _) = try StoreTests().fixture()
    var task = original
    task.rule = .daily(timeZone: "UTC", hour: 0, minute: 0)
    task.scheduleEndUTC = Date(timeIntervalSince1970: 86400)
    let memory = MemoryPersistence()
    let store = try SchedulingStore(persistence: memory)
    try await store.add(task, expectedVersion: 0)
    try await store.activate(
      taskID: task.id, grant: grant(task), now: task.createdAt, expectedVersion: 1)
    _ = try await store.enqueueDue(now: Date(timeIntervalSince1970: 86400 * 5), expectedVersion: 2)
    #expect(await store.snapshot().tasks[task.id]?.occurrenceCount == 2)
    var malformed = await store.snapshot()
    malformed.tasks[task.id]?.occurrenceCount = -1
    let invalidBytes = try JSONEncoder().encode(malformed)
    memory.data = invalidBytes
    #expect(throws: SchedulingError.invalidValue) { try SchedulingStore(persistence: memory) }
    #expect(try memory.read() == invalidBytes)
    #expect(throws: SchedulingError.invalidValue) {
      try ScheduledSummary(
        scope: task.scope, runID: UUID(), pageID: task.pageID, baseRevision: UUID(),
        source: "source", text: String(repeating: "x", count: 1024 * 1024 + 1), providerID: "p",
        modelID: "m", createdAt: task.createdAt)
    }
  }
}

extension LifecycleTests {
  @Test func backgroundPolicySurvivesRestartAndRevisionStillRequiresActivation() async throws {
    let (source, _) = try StoreTests().fixture()
    let task = try ScheduledTask(scope: source.scope, pageID: source.pageID,
      allowedBlockIDs: source.allowedBlockIDs, prompt: source.prompt,
      providerBindingID: source.providerBindingID, rule: source.rule, budget: source.budget,
      createdAt: source.createdAt, action: source.action, executionPolicy: .backgroundAllowed)
    let memory = MemoryPersistence(), store = try SchedulingStore(persistence: memory)
    let now = Date(timeIntervalSince1970: 100)
    try await store.add(task, expectedVersion: 0)
    try await store.activate(taskID: task.id, grant: grant(task), now: now, expectedVersion: 1)
    let restored = try SchedulingStore(persistence: memory)
    #expect(await restored.snapshot().tasks[task.id]?.executionPolicy == .backgroundAllowed)
    let intent = ScheduledIntent(rule: source.rule, prompt: "Changed content",
      allowedBlockIDs: source.allowedBlockIDs, providerBindingID: source.providerBindingID,
      action: source.action, budget: source.budget)
    try await restored.revise(taskID: task.id, intent: intent, grant: grant(task), now: now,
      expectedGeneration: 1, expectedVersion: 2)
    let revised = try #require(await restored.snapshot().tasks[task.id])
    #expect(revised.executionPolicy == .backgroundAllowed && revised.lifecycle == .awaitingActivation)
    let restarted = try SchedulingStore(persistence: memory)
    #expect(try await restarted.enqueueDue(now: Date(timeIntervalSince1970: 10000), expectedVersion: 3).isEmpty)
  }
}

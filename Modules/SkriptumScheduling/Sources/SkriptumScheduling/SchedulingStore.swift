import Foundation

public struct SchedulingState: Codable, Equatable, Sendable {
  public static let maximumFileBytes = 32 * 1024 * 1024
  public var schemaVersion = 1, version = 0
  public var tasks: [UUID: ScheduledTask] = [:], runs: [UUID: ScheduledRun] = [:],
    proposals: [UUID: ScheduledProposal] = [:]
  public var summaries: [UUID: ScheduledSummary] = [:]
  public var missedOccurrences: [UUID: MissedOccurrenceAudit] = [:]
  public var ledger = BudgetLedger()
  public init() {}
  private enum CodingKeys: String, CodingKey {
    case schemaVersion, version, tasks, runs, proposals, ledger, summaries, missedOccurrences
  }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
    guard schemaVersion == 1 else { throw SchedulingError.unsupportedSchema }
    version = try c.decode(Int.self, forKey: .version)
    tasks = try c.decode([UUID: ScheduledTask].self, forKey: .tasks)
    runs = try c.decode([UUID: ScheduledRun].self, forKey: .runs)
    proposals = try c.decode([UUID: ScheduledProposal].self, forKey: .proposals)
    ledger = try c.decode(BudgetLedger.self, forKey: .ledger)
    summaries = try c.decodeIfPresent([UUID: ScheduledSummary].self, forKey: .summaries) ?? [:]
    missedOccurrences =
      try c.decodeIfPresent([UUID: MissedOccurrenceAudit].self, forKey: .missedOccurrences) ?? [:]
    // Before lifecycle revision existed the current task was the historical
    // intent too. Materialize that legacy capture in memory without a disk write.
    for id in runs.keys {
      guard let run = runs[id], let task = tasks[run.occurrence.taskID] else { continue }
      if run.capturedPageID == nil { runs[id]?.capturedPageID = task.pageID }
      if run.capturedAllowedBlockIDs == nil {
        runs[id]?.capturedAllowedBlockIDs = task.allowedBlockIDs
      }
      if run.capturedAction == nil { runs[id]?.capturedAction = task.action }
    }
    try validate()
  }
  public func validate() throws {
    guard schemaVersion == 1 else { throw SchedulingError.unsupportedSchema }
    guard version >= 0, version < Int.max, summaries.count <= 1000,
      missedOccurrences.count <= 10000, tasks.count <= 1000, runs.count <= 10000,
      proposals.count <= 1000, Set(runs.values.map(\.occurrence)).count == runs.count
    else { throw SchedulingError.invalidValue }
    for (id, task) in tasks {
      guard id == task.id else { throw SchedulingError.invalidValue }
      try task.validate()
    }
    try ledger.validate()
    for (id, run) in runs {
      guard id == run.id, let task = tasks[run.occurrence.taskID], run.scope == task.scope,
        run.occurrence.generation > 0, run.occurrence.generation <= task.generation,
        run.occurrence.scheduledUTC.timeIntervalSince1970.isFinite, (0...3).contains(run.attempts),
        run.providerRequestReference.map({ !$0.isEmpty && $0.utf8.count <= 256 }) ?? true
      else { throw SchedulingError.invalidValue }
      guard run.usedFences.count == run.attempts, run.usedFences.count <= 3,
        run.lease.map({ run.usedFences.contains($0.fence) }) ?? (run.attempts == 0)
      else { throw SchedulingError.invalidValue }
      guard run.capturedPageID == task.pageID, let captured = run.capturedAllowedBlockIDs,
        captured.count <= 10000, run.capturedAction != nil
      else { throw SchedulingError.invalidValue }
      if run.occurrence.generation == task.generation {
        guard captured == task.allowedBlockIDs, run.capturedAction == task.action else {
          throw SchedulingError.invalidValue
        }
      }
      if let lease = run.lease {
        guard lease.expiresAt.timeIntervalSince1970.isFinite else {
          throw SchedulingError.invalidValue
        }
      }
      if [
        .leased, .authorized, .reserved, .dispatching, .running, .proposalReady, .completed,
        .executionUncertain,
      ].contains(run.state) {
        guard run.lease != nil, run.attempts > 0 else { throw SchedulingError.invalidValue }
      }
      if let reservation = run.reservationID {
        guard let record = ledger.reservations[id], record.id == reservation,
          record.scope == run.scope, record.taskID == run.occurrence.taskID
        else { throw SchedulingError.invalidValue }
      }
      if [.reserved, .dispatching, .running, .proposalReady, .completed, .executionUncertain]
        .contains(run.state)
      {
        guard run.reservationID != nil else { throw SchedulingError.invalidValue }
      }
      if let record = ledger.reservations[id] {
        if [.leased, .authorized, .reserved, .dispatching, .running].contains(run.state) {
          guard record.state == .held else { throw SchedulingError.invalidValue }
        }
        if run.state == .executionUncertain {
          guard record.state == .uncertain || record.state == .settled else {
            throw SchedulingError.invalidValue
          }
        }
        if [.completed, .proposalReady].contains(run.state) {
          guard record.state == .held || record.state == .settled else {
            throw SchedulingError.invalidValue
          }
        }
      }
    }
    for record in ledger.reservations.values {
      guard runs[record.runID]?.scope == record.scope else { throw SchedulingError.invalidValue }
    }
    for (id, proposal) in proposals {
      guard id == proposal.id, let run = runs[proposal.runID], run.scope == proposal.scope,
        let task = tasks[run.occurrence.taskID], task.pageID == proposal.pageID,
        run.capturedPageID == proposal.pageID,
        run.capturedAction == .proposal,
        proposal.allowedBlockIDs.isSubset(of: run.capturedAllowedBlockIDs ?? []),
        [.proposalReady, .completed].contains(run.state)
      else { throw SchedulingError.invalidValue }
      try proposal.validate()
    }
    for (id, summary) in summaries {
      guard id == summary.id, let run = runs[summary.runID], run.scope == summary.scope,
        run.capturedPageID == summary.pageID, run.capturedAction == .summary,
        run.state == .completed
      else { throw SchedulingError.invalidValue }
      try summary.validate()
    }
    for (id, audit) in missedOccurrences {
      guard id == audit.id, let task = tasks[audit.taskID], audit.generation > 0,
        audit.generation <= task.generation,
        (1...36600).contains(audit.count), audit.firstUTC.timeIntervalSince1970.isFinite,
        audit.lastUTC.timeIntervalSince1970.isFinite, audit.firstUTC <= audit.lastUTC
      else { throw SchedulingError.invalidValue }
    }
  }
}
public actor SchedulingStore {
  private var state: SchedulingState
  private let persistence: any SchedulingPersistence
  public init(persistence: any SchedulingPersistence) throws {
    self.persistence = persistence
    if let data = try persistence.read() {
      guard data.count <= SchedulingState.maximumFileBytes else {
        throw SchedulingError.persistenceTooLarge
      }
      state = try JSONDecoder().decode(SchedulingState.self, from: data)
      try state.validate()
    } else {
      state = SchedulingState()
    }
  }
  public func snapshot() -> SchedulingState { state }
  private func transact<T>(expectedVersion: Int, _ operation: (inout SchedulingState) throws -> T)
    throws -> T
  {
    guard state.version == expectedVersion else { throw SchedulingError.staleVersion }
    var candidate = state
    let result = try operation(&candidate)
    guard candidate.version < Int.max - 1 else { throw SchedulingError.invalidValue }
    candidate.version += 1
    try candidate.validate()
    let data = try JSONEncoder().encode(candidate)
    guard data.count <= SchedulingState.maximumFileBytes else {
      throw SchedulingError.persistenceTooLarge
    }
    try persistence.write(data)
    state = candidate
    return result
  }
  public func add(_ task: ScheduledTask, expectedVersion: Int) throws {
    try transact(expectedVersion: expectedVersion) { state in
      guard state.tasks[task.id] == nil, task.lifecycle == .draft, task.generation == 1,
        task.lastOccurrence == nil, task.occurrenceCount == 0, task.scheduleAnchor == task.createdAt
      else { throw SchedulingError.invalidTransition }
      try task.validate()
      state.tasks[task.id] = task
    }
  }
  public func activate(taskID: UUID, grant: ExecutionGrant, now: Date, expectedVersion: Int) throws
  {
    try transact(expectedVersion: expectedVersion) { state in
      guard var task = state.tasks[taskID],
        [.draft, .awaitingActivation, .paused].contains(task.lifecycle)
      else { throw SchedulingError.invalidTransition }
      try grant.admit(task, now: now)
      guard
        grant.role == .owner
          || state.ledger.accountCeilings[
            AccountBudgetKey(accountID: task.scope.accountID, currency: task.budget.currency)]
            == grant.accountMonthlyMicros
      else { throw SchedulingError.denied }
      if grant.role == .owner {
        try state.ledger.enrollAccountCeiling(
          accountID: task.scope.accountID, currency: task.budget.currency,
          monthlyMicros: grant.accountMonthlyMicros)
      }
      task.lifecycle = .active
      state.tasks[taskID] = task
    }
  }
  public func enqueueDue(now: Date, expectedVersion: Int) throws -> [UUID] {
    try transact(expectedVersion: expectedVersion) { state in
      guard now.timeIntervalSince1970.isFinite else { throw SchedulingError.invalidValue }
      var ids: [UUID] = []
      for id in state.tasks.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
        guard var task = state.tasks[id], task.lifecycle == .active else { continue }
        var cursor = task.lastOccurrence ?? task.scheduleAnchor.addingTimeInterval(-0.001)
        var latest: Date?
        var steps = 0
        var first: Date?
        var previous: Date?
        while steps < (task.maximumOccurrences ?? Int.max) - task.occurrenceCount,
          let next = try task.rule.next(after: cursor), next <= now,
          task.scheduleEndUTC.map({ next <= $0 }) ?? true
        {
          steps += 1
          guard steps <= 36600 else { throw SchedulingError.invalidValue }
          if first == nil { first = next }
          previous = latest
          latest = next
          cursor = next
        }
        guard let latest else { continue }
        let occurrence = OccurrenceID(taskID: id, generation: task.generation, scheduledUTC: latest)
        if !state.runs.values.contains(where: { $0.occurrence == occurrence }) {
          var run = ScheduledRun(occurrence: occurrence, scope: task.scope)
          run.capturedPageID = task.pageID
          run.capturedAllowedBlockIDs = task.allowedBlockIDs
          run.capturedAction = task.action
          state.runs[run.id] = run
          ids.append(run.id)
        }
        if steps > 1, let first, let previous {
          let audit = MissedOccurrenceAudit(
            id: UUID(), taskID: id, generation: task.generation, firstUTC: first, lastUTC: previous,
            count: steps - 1)
          state.missedOccurrences[audit.id] = audit
        }
        let total = task.occurrenceCount.addingReportingOverflow(steps)
        guard !total.overflow else { throw SchedulingError.invalidValue }
        task.occurrenceCount = total.partialValue
        task.lastOccurrence = latest
        state.tasks[id] = task
      }
      return ids
    }
  }
  private static func eligibleRun(_ state: SchedulingState, _ id: UUID) throws -> (
    ScheduledRun, ScheduledTask
  ) {
    guard let run = state.runs[id], let task = state.tasks[run.occurrence.taskID],
      task.lifecycle == .active, run.occurrence.generation == task.generation
    else { throw SchedulingError.invalidTransition }
    return (run, task)
  }
  public func claim(runID: UUID, lease: RunLease, now: Date, expectedVersion: Int) throws {
    try transact(expectedVersion: expectedVersion) { state in
      let (run, _) = try Self.eligibleRun(state, runID)
      state.runs[runID] = try RunStateMachine.claim(run, lease: lease, now: now)
    }
  }
  public func authorize(
    runID: UUID, fence: UUID, grant: ExecutionGrant, now: Date, expectedVersion: Int
  ) throws {
    try transact(expectedVersion: expectedVersion) { state in
      let (run, task) = try Self.eligibleRun(state, runID)
      try grant.admit(task, now: now)
      state.runs[runID] = try RunStateMachine.transition(
        run, to: .authorized, fence: fence, now: now)
    }
  }
  public func reserve(
    runID: UUID, fence: UUID, quote: BudgetQuote, expectedQuoteVersion: String, now: Date,
    expectedVersion: Int
  ) throws {
    try transact(expectedVersion: expectedVersion) { state in
      let (run, task) = try Self.eligibleRun(state, runID)
      var changed = try RunStateMachine.transition(run, to: .reserved, fence: fence, now: now)
      let record = try state.ledger.reserve(
        runID: runID, taskID: task.id, scope: run.scope, period: BudgetLedger.month(for: now),
        policy: task.budget, quote: quote, now: now, expectedQuoteVersion: expectedQuoteVersion)
      changed.reservationID = record.id
      state.runs[runID] = changed
    }
  }
  public func dispatch(
    runID: UUID, fence: UUID, requestReference: String, grant: ExecutionGrant,
    expectedQuoteVersion: String, now: Date, expectedVersion: Int
  ) throws {
    try transact(expectedVersion: expectedVersion) { state in
      let (run, task) = try Self.eligibleRun(state, runID)
      try grant.admit(task, now: now)
      guard let reservation = state.ledger.reservations[runID], reservation.quote.expiresAt > now,
        reservation.quote.version == expectedQuoteVersion
      else { throw SchedulingError.budgetDenied }
      var changed = try RunStateMachine.transition(run, to: .dispatching, fence: fence, now: now)
      changed.providerRequestReference = requestReference
      state.runs[runID] = changed
    }
  }
  public func started(runID: UUID, fence: UUID, now: Date, expectedVersion: Int) throws {
    try transact(expectedVersion: expectedVersion) { state in
      let (run, _) = try Self.eligibleRun(state, runID)
      state.runs[runID] = try RunStateMachine.transition(run, to: .running, fence: fence, now: now)
    }
  }
  /// No provider request has been dispatched. Only this boundary may release a
  /// reservation automatically; failures after dispatch remain uncertain.
  public func rejectBeforeDispatch(runID: UUID, fence: UUID, reason: RunState, now: Date, expectedVersion: Int) throws {
    try transact(expectedVersion: expectedVersion) { state in
      guard var run = state.runs[runID], [.leased, .authorized, .reserved].contains(run.state),
        [.denied, .budgetDenied, .failed].contains(reason) else { throw SchedulingError.invalidTransition }
      try RunStateMachine.requireLease(run, fence: fence, now: now)
      run.state = reason
      if state.ledger.reservations[runID] != nil { try state.ledger.release(runID: runID) }
      state.runs[runID] = run
    }
  }
  public func complete(
    runID: UUID, fence: UUID, grant: ExecutionGrant, now: Date, expectedVersion: Int
  ) throws {
    try transact(expectedVersion: expectedVersion) { state in
      let (run, task) = try Self.eligibleRun(state, runID)
      try grant.admit(task, now: now)
      state.runs[runID] = try RunStateMachine.transition(
        run, to: .completed, fence: fence, now: now)
    }
  }
  public func recordProposal(
    _ proposal: ScheduledProposal, fence: UUID, grant: ExecutionGrant, now: Date,
    expectedVersion: Int
  ) throws {
    try transact(expectedVersion: expectedVersion) { state in
      let (run, task) = try Self.eligibleRun(state, proposal.runID)
      try grant.admit(task, now: now)
      guard task.action == .proposal, proposal.scope == run.scope,
        state.proposals[proposal.id] == nil
      else {
        throw SchedulingError.denied
      }
      state.runs[run.id] = try RunStateMachine.transition(
        run, to: .proposalReady, fence: fence, now: now)
      state.proposals[proposal.id] = proposal
    }
  }
  public func uncertain(runID: UUID, fence: UUID, now: Date, expectedVersion: Int) throws {
    try transact(expectedVersion: expectedVersion) { state in
      let (run, _) = try Self.eligibleRun(state, runID)
      state.runs[runID] = try RunStateMachine.transition(
        run, to: .executionUncertain, fence: fence, now: now)
      try state.ledger.markUncertain(runID: runID)
    }
  }
  public func settle(runID: UUID, actualMicros: Int64, expectedVersion: Int) throws {
    try transact(expectedVersion: expectedVersion) { state in
      guard let run = state.runs[runID],
        [.completed, .proposalReady, .executionUncertain, .cancelled].contains(run.state)
      else { throw SchedulingError.invalidTransition }
      try state.ledger.settle(runID: runID, actualMicros: actualMicros)
    }
  }
  public func recoverExpired(now: Date, expectedVersion: Int) throws {
    try transact(expectedVersion: expectedVersion) { state in
      for id in state.runs.keys {
        guard var run = state.runs[id], [.dispatching, .running].contains(run.state),
          let lease = run.lease, lease.expiresAt <= now
        else { continue }
        run.state = .executionUncertain
        state.runs[id] = run
        try state.ledger.markUncertain(runID: id)
      }
    }
  }
  private static func fencePriorRuns(_ state: inout SchedulingState, taskID: UUID) throws {
    for id in state.runs.keys {
      guard var run = state.runs[id], run.occurrence.taskID == taskID,
        ![.completed, .proposalReady, .cancelled].contains(run.state)
      else { continue }
      if let reservation = state.ledger.reservations[id],
        reservation.state != .settled && reservation.state != .released
      {
        if [.dispatching, .running, .executionUncertain].contains(run.state) {
          try state.ledger.markUncertain(runID: id)
        } else {
          try state.ledger.release(runID: id)
        }
      }
      run.state = .cancelled
      state.runs[id] = run
    }
  }
  public func pause(
    taskID: UUID, grant: ExecutionGrant, now: Date, expectedGeneration: Int, expectedVersion: Int
  ) throws {
    try transact(expectedVersion: expectedVersion) { state in
      guard var task = state.tasks[taskID], task.lifecycle == .active,
        task.generation == expectedGeneration
      else { throw SchedulingError.invalidTransition }
      try grant.admit(task, now: now)
      task.generation += 1
      task.lifecycle = .paused
      state.tasks[taskID] = task
      try Self.fencePriorRuns(&state, taskID: taskID)
    }
  }
  public func revise(
    taskID: UUID, intent: ScheduledIntent, grant: ExecutionGrant, now: Date,
    expectedGeneration: Int, expectedVersion: Int
  ) throws {
    try transact(expectedVersion: expectedVersion) { state in
      guard let old = state.tasks[taskID], old.lifecycle != .cancelled,
        old.generation == expectedGeneration
      else { throw SchedulingError.invalidTransition }
      try grant.admit(old, now: now)
      var replacement = try ScheduledTask(
        id: old.id, scope: old.scope, pageID: old.pageID, allowedBlockIDs: intent.allowedBlockIDs,
        prompt: intent.prompt, providerBindingID: intent.providerBindingID, rule: intent.rule,
        budget: intent.budget, createdAt: old.createdAt, action: intent.action,
        scheduleEndUTC: intent.scheduleEndUTC, maximumOccurrences: intent.maximumOccurrences,
        executionPolicy: old.executionPolicy)
      replacement.scheduleAnchor = now
      replacement.generation = old.generation + 1
      replacement.lifecycle = old.lifecycle == .paused ? .paused : .awaitingActivation
      try replacement.validate()
      state.tasks[taskID] = replacement
      try Self.fencePriorRuns(&state, taskID: taskID)
    }
  }
  public func recordSummary(
    _ summary: ScheduledSummary, fence: UUID, grant: ExecutionGrant, now: Date, expectedVersion: Int
  ) throws {
    try transact(expectedVersion: expectedVersion) { state in
      let (run, task) = try Self.eligibleRun(state, summary.runID)
      try grant.admit(task, now: now)
      guard task.action == .summary, summary.scope == run.scope, summary.pageID == task.pageID,
        state.summaries[summary.id] == nil
      else { throw SchedulingError.denied }
      try summary.validate()
      state.runs[run.id] = try RunStateMachine.transition(
        run, to: .completed, fence: fence, now: now)
      state.summaries[summary.id] = summary
    }
  }
  public func cancel(taskID: UUID, expectedGeneration: Int, expectedVersion: Int) throws {
    try transact(expectedVersion: expectedVersion) { state in
      guard var task = state.tasks[taskID] else { throw SchedulingError.staleVersion }
      if task.lifecycle == .cancelled {
        guard
          task.generation == expectedGeneration
            || (expectedGeneration < Int.max && task.generation == expectedGeneration + 1)
        else { throw SchedulingError.staleVersion }
        return
      }
      guard task.generation == expectedGeneration else { throw SchedulingError.staleVersion }
      task.generation += 1
      task.lifecycle = .cancelled
      state.tasks[taskID] = task
      try Self.fencePriorRuns(&state, taskID: taskID)

    }
  }
}

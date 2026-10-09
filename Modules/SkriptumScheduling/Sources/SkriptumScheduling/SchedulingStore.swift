import Foundation

public struct SchedulingState: Codable, Equatable, Sendable {
  public static let maximumFileBytes = 32 * 1024 * 1024
  public var schemaVersion = 1, version = 0
  public var tasks: [UUID: ScheduledTask] = [:], runs: [UUID: ScheduledRun] = [:],
    proposals: [UUID: ScheduledProposal] = [:]
  public var ledger = BudgetLedger()
  public init() {}
  public func validate() throws {
    guard schemaVersion == 1 else { throw SchedulingError.unsupportedSchema }
    guard version >= 0, version < Int.max, tasks.count <= 1000, runs.count <= 10000,
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
        proposal.allowedBlockIDs.isSubset(of: task.allowedBlockIDs),
        [.proposalReady, .completed].contains(run.state)
      else { throw SchedulingError.invalidValue }
      try proposal.validate()
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
        task.lastOccurrence == nil
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
        var cursor = task.lastOccurrence ?? task.createdAt.addingTimeInterval(-0.001)
        var latest: Date?
        var steps = 0
        while let next = try task.rule.next(after: cursor), next <= now {
          steps += 1
          guard steps <= 36600 else { throw SchedulingError.invalidValue }
          latest = next
          cursor = next
        }
        guard let latest else { continue }
        let occurrence = OccurrenceID(taskID: id, generation: task.generation, scheduledUTC: latest)
        if !state.runs.values.contains(where: { $0.occurrence == occurrence }) {
          let run = ScheduledRun(occurrence: occurrence, scope: task.scope)
          state.runs[run.id] = run
          ids.append(run.id)
        }
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
      guard proposal.scope == run.scope, state.proposals[proposal.id] == nil else {
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
  }
}

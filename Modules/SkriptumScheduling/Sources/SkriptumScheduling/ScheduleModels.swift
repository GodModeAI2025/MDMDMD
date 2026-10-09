import Foundation

public enum SchedulingError: Error, Equatable {
  case invalidValue, unsupportedSchema, invalidTransition, staleVersion, denied, expiredLease,
    budgetDenied, executionUncertain, staleProposal, persistenceTooLarge, unsafeFile
}
public struct SchedulingScope: Codable, Hashable, Sendable {
  public let accountID: UUID, libraryID: UUID, spaceID: UUID
  public init(accountID: UUID, libraryID: UUID, spaceID: UUID) {
    self.accountID = accountID
    self.libraryID = libraryID
    self.spaceID = spaceID
  }
}
public enum TaskLifecycle: String, Codable, Sendable {
  case draft, awaitingActivation, active, paused, cancelled
}
public enum ScheduledAction: String, Codable, Sendable { case proposal, summary }
public struct ScheduledTask: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID, scope: SchedulingScope, pageID: UUID, providerBindingID: UUID,
    createdAt: Date
  public var generation: Int, rule: ScheduleRule, prompt: String, allowedBlockIDs: Set<UUID>,
    action: ScheduledAction, budget: BudgetPolicy, lifecycle: TaskLifecycle, lastOccurrence: Date?
  public init(
    id: UUID = UUID(), scope: SchedulingScope, pageID: UUID, allowedBlockIDs: Set<UUID>,
    prompt: String, providerBindingID: UUID, rule: ScheduleRule, budget: BudgetPolicy,
    createdAt: Date, action: ScheduledAction = .proposal
  ) throws {
    self.id = id
    self.scope = scope
    self.pageID = pageID
    self.allowedBlockIDs = allowedBlockIDs
    self.prompt = prompt
    self.providerBindingID = providerBindingID
    self.rule = rule
    self.budget = budget
    self.createdAt = createdAt
    self.action = action
    generation = 1
    lifecycle = .draft
    try validate()
  }
  public func validate() throws {
    guard generation > 0, generation < Int.max, createdAt.timeIntervalSince1970.isFinite,
      !prompt.isEmpty, prompt.utf8.count <= 16 * 1024, allowedBlockIDs.count <= 10000,
      action != .proposal || !allowedBlockIDs.isEmpty,
      lastOccurrence?.timeIntervalSince1970.isFinite ?? true
    else { throw SchedulingError.invalidValue }
    try rule.validate()
    try budget.validate()
  }
}
public enum SchedulingRole: String, Codable, Sendable { case owner, editor, viewer }
/// Admission input supplied by an authenticated backend. Constructing this value
/// locally does not prove server authentication, inheritance or permission.
public struct ExecutionGrant: Codable, Equatable, Sendable {
  public let scope: SchedulingScope, taskID: UUID, generation: Int, accountMonthlyMicros: Int64,
    expiresAt: Date, role: SchedulingRole, editorDelegated: Bool, readablePageIDs: Set<UUID>,
    readableBlockIDs: Set<UUID>
  public init(
    scope: SchedulingScope, taskID: UUID, generation: Int, accountMonthlyMicros: Int64,
    expiresAt: Date, role: SchedulingRole, editorDelegated: Bool = false,
    readablePageIDs: Set<UUID>, readableBlockIDs: Set<UUID>
  ) {
    self.scope = scope
    self.taskID = taskID
    self.generation = generation
    self.accountMonthlyMicros = accountMonthlyMicros
    self.expiresAt = expiresAt
    self.role = role
    self.editorDelegated = editorDelegated
    self.readablePageIDs = readablePageIDs
    self.readableBlockIDs = readableBlockIDs
  }
  public func admit(_ task: ScheduledTask, now: Date) throws {
    guard accountMonthlyMicros >= 0, scope == task.scope, taskID == task.id,
      generation == task.generation, expiresAt > now,
      role == .owner || role == .editor && editorDelegated, readablePageIDs.contains(task.pageID),
      task.allowedBlockIDs.isSubset(of: readableBlockIDs)
    else { throw SchedulingError.denied }
  }
}
public struct OccurrenceID: Codable, Hashable, Sendable {
  public let taskID: UUID, generation: Int, scheduledUTC: Date
}
public enum RunState: String, Codable, Sendable {
  case queued, leased, authorized, reserved, dispatching, running, proposalReady, completed,
    cancelled, denied, budgetDenied, failed, executionUncertain
}
public struct RunLease: Codable, Equatable, Sendable {
  public let workerID: UUID, fence: UUID, expiresAt: Date
  public init(workerID: UUID, fence: UUID = UUID(), expiresAt: Date) {
    self.workerID = workerID
    self.fence = fence
    self.expiresAt = expiresAt
  }
}
public struct ScheduledRun: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID, occurrence: OccurrenceID, scope: SchedulingScope
  public var usedFences: Set<UUID> = []
  public var state: RunState, attempts: Int, lease: RunLease?, reservationID: UUID?,
    providerRequestReference: String?
  public init(id: UUID = UUID(), occurrence: OccurrenceID, scope: SchedulingScope) {
    self.id = id
    self.occurrence = occurrence
    self.scope = scope
    state = .queued
    attempts = 0
  }
}

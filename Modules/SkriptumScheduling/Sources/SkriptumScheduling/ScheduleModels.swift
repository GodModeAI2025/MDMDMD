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
  public var scheduleAnchor: Date
  public var scheduleEndUTC: Date?
  public var maximumOccurrences: Int?
  public var occurrenceCount = 0
  public init(
    id: UUID = UUID(), scope: SchedulingScope, pageID: UUID, allowedBlockIDs: Set<UUID>,
    prompt: String, providerBindingID: UUID, rule: ScheduleRule, budget: BudgetPolicy,
    createdAt: Date, action: ScheduledAction = .proposal, scheduleEndUTC: Date? = nil,
    maximumOccurrences: Int? = nil
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
    scheduleAnchor = createdAt
    self.scheduleEndUTC = scheduleEndUTC
    self.maximumOccurrences = maximumOccurrences
    self.action = action
    generation = 1
    lifecycle = .draft
    try validate()
  }
  private enum CodingKeys: String, CodingKey {
    case id, scope, pageID, providerBindingID, createdAt, generation, rule, prompt, allowedBlockIDs,
      action, budget, lifecycle, lastOccurrence, scheduleAnchor, scheduleEndUTC, maximumOccurrences,
      occurrenceCount
  }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    scope = try c.decode(SchedulingScope.self, forKey: .scope)
    pageID = try c.decode(UUID.self, forKey: .pageID)
    providerBindingID = try c.decode(UUID.self, forKey: .providerBindingID)
    createdAt = try c.decode(Date.self, forKey: .createdAt)
    generation = try c.decode(Int.self, forKey: .generation)
    rule = try c.decode(ScheduleRule.self, forKey: .rule)
    prompt = try c.decode(String.self, forKey: .prompt)
    allowedBlockIDs = try c.decode(Set<UUID>.self, forKey: .allowedBlockIDs)
    action = try c.decode(ScheduledAction.self, forKey: .action)
    budget = try c.decode(BudgetPolicy.self, forKey: .budget)
    lifecycle = try c.decode(TaskLifecycle.self, forKey: .lifecycle)
    lastOccurrence = try c.decodeIfPresent(Date.self, forKey: .lastOccurrence)
    scheduleAnchor = try c.decodeIfPresent(Date.self, forKey: .scheduleAnchor) ?? createdAt
    scheduleEndUTC = try c.decodeIfPresent(Date.self, forKey: .scheduleEndUTC)
    maximumOccurrences = try c.decodeIfPresent(Int.self, forKey: .maximumOccurrences)
    occurrenceCount = try c.decodeIfPresent(Int.self, forKey: .occurrenceCount) ?? 0
    try validate()
  }

  public func validate() throws {
    guard scheduleAnchor.timeIntervalSince1970.isFinite, scheduleAnchor >= createdAt,
      scheduleEndUTC.map({ $0.timeIntervalSince1970.isFinite && $0 >= scheduleAnchor }) ?? true,
      maximumOccurrences.map({ (1...1_000_000).contains($0) }) ?? true,
      occurrenceCount >= 0, occurrenceCount <= (maximumOccurrences ?? Int.max),
      generation > 0, generation < Int.max, createdAt.timeIntervalSince1970.isFinite,
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
      role == .owner || role == .editor && editorDelegated && task.action == .proposal,
      readablePageIDs.contains(task.pageID),
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
  public var capturedPageID: UUID?
  public var capturedAllowedBlockIDs: Set<UUID>?
  public var capturedAction: ScheduledAction?
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

public struct ScheduledIntent: Sendable {
  public let rule: ScheduleRule
  public let prompt: String
  public let allowedBlockIDs: Set<UUID>
  public let providerBindingID: UUID
  public let action: ScheduledAction
  public let budget: BudgetPolicy
  public let scheduleEndUTC: Date?
  public let maximumOccurrences: Int?
  public init(
    rule: ScheduleRule, prompt: String, allowedBlockIDs: Set<UUID>, providerBindingID: UUID,
    action: ScheduledAction, budget: BudgetPolicy, scheduleEndUTC: Date? = nil,
    maximumOccurrences: Int? = nil
  ) {
    self.rule = rule
    self.prompt = prompt
    self.allowedBlockIDs = allowedBlockIDs
    self.providerBindingID = providerBindingID
    self.action = action
    self.budget = budget
    self.scheduleEndUTC = scheduleEndUTC
    self.maximumOccurrences = maximumOccurrences
  }
}
public struct MissedOccurrenceAudit: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID, taskID: UUID, generation: Int, firstUTC: Date, lastUTC: Date, count: Int
}

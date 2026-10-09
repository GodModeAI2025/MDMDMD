import Foundation

public struct BudgetPolicy: Codable, Equatable, Sendable {
  public var currency: String
  public var perRunMicros: Int64
  public var monthlyMicros: Int64
  public var inputTokens: Int
  public var outputTokens: Int
  public init(
    currency: String, perRunMicros: Int64, monthlyMicros: Int64, inputTokens: Int, outputTokens: Int
  ) {
    self.currency = currency
    self.perRunMicros = perRunMicros
    self.monthlyMicros = monthlyMicros
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
  }
  public func validate() throws {
    guard currency.utf8.count == 3, currency.utf8.allSatisfy({ (65...90).contains($0) }),
      perRunMicros >= 0, monthlyMicros >= perRunMicros, (1...2_000_000).contains(inputTokens),
      (1...2_000_000).contains(outputTokens)
    else { throw SchedulingError.invalidValue }
  }
}
public struct BudgetQuote: Codable, Equatable, Sendable {
  public let currency: String
  public let maximumMicros: Int64
  public let inputTokens: Int
  public let outputTokens: Int
  public let version: String
  public let expiresAt: Date
  public init(
    currency: String, maximumMicros: Int64, inputTokens: Int, outputTokens: Int, version: String,
    expiresAt: Date
  ) {
    self.currency = currency
    self.maximumMicros = maximumMicros
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.version = version
    self.expiresAt = expiresAt
  }
}
public enum ReservationState: String, Codable, Sendable { case held, uncertain, settled, released }
public struct BudgetReservation: Codable, Equatable, Sendable {
  public let id: UUID
  public let runID: UUID
  public let taskID: UUID
  public let scope: SchedulingScope
  public let period: String
  public let quote: BudgetQuote
  public var state: ReservationState
  public var actualMicros: Int64?
}
/// Monthly usage aggregates across all libraries and Spaces of an account in
/// the same currency; moving a task cannot escape the supplied owner ceiling.
public struct AccountBudgetKey: Codable, Hashable, Sendable {
  public let accountID: UUID
  public let currency: String
}
public struct BudgetLedger: Codable, Equatable, Sendable {
  public private(set) var accountCeilings: [AccountBudgetKey: Int64] = [:]
  public private(set) var reservations: [UUID: BudgetReservation] = [:]
  public init() {}
  /// Enrollment input must come from the verified owner grant, never task intent.
  /// Changing an enrolled ceiling requires a separately authorized future API.
  public mutating func enrollAccountCeiling(accountID: UUID, currency: String, monthlyMicros: Int64)
    throws
  {
    guard monthlyMicros >= 0, currency.utf8.count == 3,
      currency.utf8.allSatisfy({ (65...90).contains($0) })
    else { throw SchedulingError.invalidValue }
    let key = AccountBudgetKey(accountID: accountID, currency: currency)
    if let current = accountCeilings[key] {
      guard current == monthlyMicros else { throw SchedulingError.denied }
      return
    }
    guard accountCeilings.count < 1000 else { throw SchedulingError.invalidValue }
    accountCeilings[key] = monthlyMicros
  }
  /// Imports verified local legacy ledgers without lowering an existing hold.
  /// Scope/owner admission is the caller's responsibility; conflicting ceilings
  /// or immutable run facts fail instead of silently resetting usage.
  public mutating func mergeConservatively(_ incoming: BudgetLedger) throws {
    try validate(); try incoming.validate()
    var candidate = self
    for (key, value) in incoming.accountCeilings {
      try candidate.enrollAccountCeiling(accountID: key.accountID, currency: key.currency, monthlyMicros: value)
    }
    for (id, value) in incoming.reservations {
      if let prior = candidate.reservations[id] {
        guard prior.taskID == value.taskID, prior.scope == value.scope,
              prior.period == value.period, prior.quote == value.quote else { throw SchedulingError.denied }
        if prior.state == .settled && value.state == .settled {
          guard prior.actualMicros == value.actualMicros else { throw SchedulingError.denied }
        }
        // Existing confirmed settlement is authoritative for this exact run.
        // Importing an older local hold cannot undo it. Otherwise preserve the
        // largest possible usage, never infer a refund from a legacy release.
        if prior.state != .settled {
          if prior.state == .released && value.state != .released {
            candidate.reservations[id] = value
          } else if prior.state == .held && value.state == .uncertain {
            var updated = prior; updated.state = .uncertain; candidate.reservations[id] = updated
          }
        }
      } else { candidate.reservations[id] = value }
    }
    try candidate.validate(); self = candidate
  }
  public static func month(for date: Date) throws -> String {
    guard date.timeIntervalSince1970.isFinite else { throw SchedulingError.invalidValue }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let parts = calendar.dateComponents([.year, .month], from: date)
    guard let year = parts.year, let month = parts.month, (1...9999).contains(year) else {
      throw SchedulingError.invalidValue
    }
    return String(format: "%04d-%02d", year, month)
  }
  public mutating func reserve(
    runID: UUID, taskID: UUID, scope: SchedulingScope, period: String, policy: BudgetPolicy,
    quote: BudgetQuote, now: Date, expectedQuoteVersion: String
  ) throws -> BudgetReservation {
    try validate()
    try policy.validate()
    guard period == (try Self.month(for: now)), quote.expiresAt > now,
      quote.version == expectedQuoteVersion, quote.currency == policy.currency,
      quote.maximumMicros >= 0, quote.maximumMicros <= policy.perRunMicros,
      (0...policy.inputTokens).contains(quote.inputTokens),
      (0...policy.outputTokens).contains(quote.outputTokens), !quote.version.isEmpty,
      quote.version.utf8.count <= 128
    else { throw SchedulingError.budgetDenied }
    if let prior = reservations[runID] {
      guard prior.taskID == taskID, prior.scope == scope, prior.period == period,
        prior.quote == quote, prior.state != .released
      else { throw SchedulingError.invalidTransition }
      return prior
    }
    guard
      let accountCeiling = accountCeilings[
        AccountBudgetKey(accountID: scope.accountID, currency: policy.currency)]
    else { throw SchedulingError.denied }
    var committed: Int64 = 0
    var taskCommitted: Int64 = 0
    for record in reservations.values
    where record.scope.accountID == scope.accountID && record.period == period
      && record.quote.currency == quote.currency
    {
      let amount: Int64
      switch record.state {
      case .released: amount = 0
      case .settled:
        guard let actual = record.actualMicros else { throw SchedulingError.invalidValue }
        amount = actual
      case .held, .uncertain: amount = record.quote.maximumMicros
      }
      let sum = committed.addingReportingOverflow(amount)
      guard !sum.overflow else { throw SchedulingError.budgetDenied }
      committed = sum.partialValue
      if record.taskID == taskID {
        let taskSum = taskCommitted.addingReportingOverflow(amount)
        guard !taskSum.overflow else { throw SchedulingError.budgetDenied }
        taskCommitted = taskSum.partialValue
      }
    }
    let sum = committed.addingReportingOverflow(quote.maximumMicros)
    let taskSum = taskCommitted.addingReportingOverflow(quote.maximumMicros)
    guard !sum.overflow, sum.partialValue <= accountCeiling, !taskSum.overflow,
      taskSum.partialValue <= policy.monthlyMicros, reservations.count < 10000
    else { throw SchedulingError.budgetDenied }
    let result = BudgetReservation(
      id: UUID(), runID: runID, taskID: taskID, scope: scope, period: period, quote: quote,
      state: .held)
    reservations[runID] = result
    return result
  }
  public mutating func markUncertain(runID: UUID) throws {
    try validate()
    guard var record = reservations[runID], record.state == .held || record.state == .uncertain
    else { throw SchedulingError.invalidTransition }
    record.state = .uncertain
    reservations[runID] = record
  }
  public mutating func settle(runID: UUID, actualMicros: Int64) throws {
    try validate()
    guard var record = reservations[runID], actualMicros >= 0,
      actualMicros <= record.quote.maximumMicros
    else { throw SchedulingError.budgetDenied }
    if record.state == .settled {
      guard record.actualMicros == actualMicros else { throw SchedulingError.invalidTransition }
      return
    }
    guard record.state == .held || record.state == .uncertain else {
      throw SchedulingError.invalidTransition
    }
    record.state = .settled
    record.actualMicros = actualMicros
    reservations[runID] = record
  }
  public mutating func release(runID: UUID) throws {
    try validate()
    guard var record = reservations[runID] else { throw SchedulingError.invalidTransition }
    if record.state == .uncertain { throw SchedulingError.executionUncertain }
    if record.state == .released { return }
    guard record.state == .held else { throw SchedulingError.invalidTransition }
    record.state = .released
    reservations[runID] = record
  }
  public func validate() throws {
    guard accountCeilings.count <= 1000,
      accountCeilings.allSatisfy({
        $0.value >= 0 && $0.key.currency.utf8.count == 3
          && $0.key.currency.utf8.allSatisfy({ (65...90).contains($0) })
      }), reservations.count <= 10000,
      Set(reservations.values.map(\.id)).count == reservations.count
    else { throw SchedulingError.invalidValue }
    for (id, record) in reservations {
      guard
        accountCeilings[
          AccountBudgetKey(accountID: record.scope.accountID, currency: record.quote.currency)]
          != nil, id == record.runID,
        record.period.range(of: "^[0-9]{4}-(0[1-9]|1[0-2])$", options: .regularExpression) != nil,
        record.quote.currency.utf8.count == 3,
        record.quote.currency.utf8.allSatisfy({ (65...90).contains($0) }),
        record.quote.maximumMicros >= 0, (0...2_000_000).contains(record.quote.inputTokens),
        (0...2_000_000).contains(record.quote.outputTokens), !record.quote.version.isEmpty,
        record.quote.version.utf8.count <= 128,
        record.quote.expiresAt.timeIntervalSince1970.isFinite,
        record.actualMicros.map({ $0 >= 0 && $0 <= record.quote.maximumMicros }) ?? true,
        record.state == .settled ? record.actualMicros != nil : record.actualMicros == nil
      else { throw SchedulingError.invalidValue }
    }
  }
}

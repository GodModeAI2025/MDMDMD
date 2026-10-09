import Foundation
import Testing

@testable import SkriptumScheduling

struct SchedulingTests {
  let scope = SchedulingScope(accountID: UUID(), libraryID: UUID(), spaceID: UUID())
  func task(rule: ScheduleRule = .oneShot(Date(timeIntervalSince1970: 100))) throws -> ScheduledTask
  {
    try ScheduledTask(
      scope: scope, pageID: UUID(), allowedBlockIDs: [UUID()], prompt: "Proofread",
      providerBindingID: UUID(), rule: rule,
      budget: BudgetPolicy(
        currency: "USD", perRunMicros: 100, monthlyMicros: 200, inputTokens: 1000,
        outputTokens: 1000), createdAt: Date(timeIntervalSince1970: 0))
  }
  @Test func recurrenceDSTAndStrictNext() throws {
    let f = ISO8601DateFormatter()
    let start = f.date(from: "2026-03-29T00:00:00Z")!
    let rule = ScheduleRule.daily(timeZone: "Europe/Berlin", hour: 2, minute: 30)
    #expect(try rule.next(after: start) == f.date(from: "2026-03-29T01:00:00Z"))
    let overlap = ScheduleRule.daily(timeZone: "Europe/Berlin", hour: 2, minute: 30)
    #expect(
      try overlap.next(after: f.date(from: "2026-10-25T00:00:00Z")!)
        == f.date(from: "2026-10-25T00:30:00Z"))
    #expect(
      try overlap.next(after: f.date(from: "2026-10-25T00:30:00Z")!)
        == f.date(from: "2026-10-26T01:30:00Z"))
    #expect(
      try ScheduleRule.weekly(timeZone: "UTC", hour: 9, minute: 0, weekdays: [2]).next(
        after: f.date(from: "2026-10-09T00:00:00Z")!) == f.date(from: "2026-10-12T09:00:00Z"))
  }
  @Test func ledgerReservesOnceAndUncertainHoldCannotRelease() throws {
    var ledger = BudgetLedger()
    var policy = BudgetPolicy(
      currency: "USD", perRunMicros: 100, monthlyMicros: 100, inputTokens: 20, outputTokens: 20)
    try ledger.enrollAccountCeiling(accountID: scope.accountID, currency: "USD", monthlyMicros: 100)
    let run = UUID()
    let period = "2026-10"
    let reservation = try ledger.reserve(
      runID: run, taskID: scope.spaceID, scope: scope, period: period, policy: policy,
      quote: BudgetQuote(
        currency: "USD", maximumMicros: 80, inputTokens: 10, outputTokens: 10, version: "v1",
        expiresAt: .distantFuture), now: Date(timeIntervalSince1970: 1_790_812_800),
      expectedQuoteVersion: "v1")
    #expect(
      try ledger.reserve(
        runID: run, taskID: scope.spaceID, scope: scope, period: period, policy: policy,
        quote: BudgetQuote(
          currency: "USD", maximumMicros: 80, inputTokens: 10, outputTokens: 10, version: "v1",
          expiresAt: .distantFuture), now: Date(timeIntervalSince1970: 1_790_812_800),
        expectedQuoteVersion: "v1") == reservation)
    #expect(throws: SchedulingError.budgetDenied) {
      try ledger.reserve(
        runID: UUID(), taskID: scope.spaceID, scope: scope, period: period, policy: policy,
        quote: BudgetQuote(
          currency: "USD", maximumMicros: 30, inputTokens: 10, outputTokens: 10, version: "v1",
          expiresAt: .distantFuture), now: Date(timeIntervalSince1970: 1_790_812_800),
        expectedQuoteVersion: "v1")
    }
    try ledger.markUncertain(runID: run)
    #expect(throws: SchedulingError.executionUncertain) { try ledger.release(runID: run) }
    try ledger.settle(runID: run, actualMicros: 70)
    try ledger.settle(runID: run, actualMicros: 70)
    #expect(throws: SchedulingError.invalidTransition) {
      try ledger.settle(runID: run, actualMicros: 69)
    }
  }
  @Test func sourceDigestUsesExactBytes() throws {
    #expect(ScheduledProposal.digest("é\r\n") != ScheduledProposal.digest("e\u{301}\r\n"))
    let page = UUID()
    let revision = UUID()
    let block = UUID()
    let run = UUID()
    let proposal = try ScheduledProposal(
      scope: scope, runID: run, pageID: page, baseRevision: revision, allowedBlockIDs: [block],
      source: "exact\r\n", replacementBlocks: [block: "new\r\n"])
    #expect(
      try proposal.admit(
        scope: scope, pageID: page, revision: revision, source: "exact\r\n",
        readableBlockIDs: [block]))
    #expect(throws: SchedulingError.staleProposal) {
      try proposal.admit(
        scope: scope, pageID: page, revision: revision, source: "exact\n", readableBlockIDs: [block]
      )
    }
  }
}

extension SchedulingTests {
  @Test func ownerBudgetCannotBeEvadedBySpaceOrMonthAndQuotesMustBeCurrent() throws {
    var ledger = BudgetLedger()
    let now = Date(timeIntervalSince1970: 1_790_812_800)
    let policy = BudgetPolicy(
      currency: "USD", perRunMicros: 100, monthlyMicros: 100, inputTokens: 20, outputTokens: 20)
    try ledger.enrollAccountCeiling(accountID: scope.accountID, currency: "USD", monthlyMicros: 100)
    let quote = BudgetQuote(
      currency: "USD", maximumMicros: 80, inputTokens: 10, outputTokens: 10, version: "v1",
      expiresAt: now.addingTimeInterval(60))
    _ = try ledger.reserve(
      runID: UUID(), taskID: scope.spaceID, scope: scope, period: "2026-10", policy: policy,
      quote: quote, now: now, expectedQuoteVersion: "v1")
    let other = SchedulingScope(accountID: scope.accountID, libraryID: UUID(), spaceID: UUID())
    #expect(throws: SchedulingError.budgetDenied) {
      try ledger.reserve(
        runID: UUID(), taskID: scope.spaceID, scope: other, period: "2026-10", policy: policy,
        quote: quote, now: now, expectedQuoteVersion: "v1")
    }
    #expect(throws: SchedulingError.budgetDenied) {
      try ledger.reserve(
        runID: UUID(), taskID: scope.spaceID, scope: scope, period: "2026-11", policy: policy,
        quote: quote, now: now, expectedQuoteVersion: "v1")
    }
    #expect(throws: SchedulingError.budgetDenied) {
      try ledger.reserve(
        runID: UUID(), taskID: scope.spaceID, scope: scope, period: "2026-10", policy: policy,
        quote: quote, now: now.addingTimeInterval(61), expectedQuoteVersion: "v1")
    }
    #expect(throws: SchedulingError.budgetDenied) {
      try ledger.reserve(
        runID: UUID(), taskID: scope.spaceID, scope: scope, period: "2026-10", policy: policy,
        quote: quote, now: now, expectedQuoteVersion: "new")
    }
  }
  @Test func overflowAndDecodedCorruptLedgerFailWithoutTrap() throws {
    var ledger = BudgetLedger()
    let now = Date(timeIntervalSince1970: 1_790_812_800)
    let policy = BudgetPolicy(
      currency: "USD", perRunMicros: Int64.max, monthlyMicros: Int64.max, inputTokens: 1,
      outputTokens: 1)
    let quote = BudgetQuote(
      currency: "USD", maximumMicros: Int64.max, inputTokens: 1, outputTokens: 1, version: "v",
      expiresAt: .distantFuture)
    try ledger.enrollAccountCeiling(
      accountID: scope.accountID, currency: "USD", monthlyMicros: Int64.max)
    _ = try ledger.reserve(
      runID: UUID(), taskID: scope.spaceID, scope: scope, period: "2026-10", policy: policy,
      quote: quote, now: now, expectedQuoteVersion: "v")
    let second = BudgetQuote(
      currency: "USD", maximumMicros: 1, inputTokens: 1, outputTokens: 1, version: "v",
      expiresAt: .distantFuture)
    #expect(throws: SchedulingError.budgetDenied) {
      try ledger.reserve(
        runID: UUID(), taskID: scope.spaceID, scope: scope, period: "2026-10", policy: policy,
        quote: second, now: now, expectedQuoteVersion: "v")
    }
    var object =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as! [String: Any]
    var pairs = object["reservations"] as! [Any]
    var record = pairs[1] as! [String: Any]
    record["state"] = "settled"
    record.removeValue(forKey: "actualMicros")
    pairs[1] = record
    object["reservations"] = pairs
    var malformed = try JSONDecoder().decode(
      BudgetLedger.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(throws: SchedulingError.invalidValue) {
      try malformed.reserve(
        runID: UUID(), taskID: scope.spaceID, scope: scope, period: "2026-10", policy: policy,
        quote: second, now: now, expectedQuoteVersion: "v")
    }
  }
  @Test func proposalWrongScopeRevisionBlocksAndPromptBoundsRejected() throws {
    let block = UUID()
    let page = UUID()
    let revision = UUID()
    let proposal = try ScheduledProposal(
      scope: scope, runID: UUID(), pageID: page, baseRevision: revision, allowedBlockIDs: [block],
      source: "original", replacementBlocks: [block: "replacement"])
    #expect(throws: SchedulingError.staleProposal) {
      try proposal.admit(
        scope: scope, pageID: page, revision: UUID(), source: "original", readableBlockIDs: [block])
    }
    #expect(throws: SchedulingError.staleProposal) {
      try proposal.admit(
        scope: scope, pageID: page, revision: revision, source: "original", readableBlockIDs: [])
    }
    #expect(throws: SchedulingError.invalidValue) {
      try ScheduledProposal(
        scope: scope, runID: UUID(), pageID: page, baseRevision: revision, allowedBlockIDs: [block],
        source: "original", replacementBlocks: [UUID(): "foreign"])
    }
    var invalid = try task()
    invalid.prompt = String(repeating: "x", count: 16 * 1024 + 1)
    #expect(throws: SchedulingError.invalidValue) { try invalid.validate() }
  }
}

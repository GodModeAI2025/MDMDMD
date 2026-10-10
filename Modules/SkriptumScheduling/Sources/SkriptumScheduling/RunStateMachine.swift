import Foundation

public enum RunStateMachine {
  public static func requireLease(_ run: ScheduledRun, fence: UUID, now: Date) throws {
    guard let lease = run.lease, lease.fence == fence, lease.expiresAt > now else {
      throw SchedulingError.expiredLease
    }
  }
  public static func claim(_ run: ScheduledRun, lease: RunLease, now: Date) throws -> ScheduledRun {
    guard now.timeIntervalSince1970.isFinite, lease.expiresAt > now,
      lease.expiresAt <= now.addingTimeInterval(900), run.attempts < 3
    else { throw SchedulingError.invalidValue }
    guard !run.usedFences.contains(lease.fence),
      [.queued, .leased, .authorized, .reserved].contains(run.state),
      run.lease?.expiresAt ?? .distantPast <= now
    else { throw SchedulingError.invalidTransition }
    var changed = run
    changed.usedFences.insert(lease.fence)
    changed.lease = lease
    changed.state = .leased
    changed.attempts += 1
    return changed
  }
  public static func transition(_ run: ScheduledRun, to target: RunState, fence: UUID, now: Date)
    throws -> ScheduledRun
  {
    try requireLease(run, fence: fence, now: now)
    let allowed: [RunState: [RunState]] = [
      .leased: [.authorized, .denied, .failed], .authorized: [.reserved, .budgetDenied, .denied],
      .reserved: [.dispatching, .denied, .failed, .budgetDenied], .dispatching: [.running, .executionUncertain],
      .running: [.completed, .proposalReady, .failed, .executionUncertain],
    ]
    guard allowed[run.state]?.contains(target) == true else {
      throw SchedulingError.invalidTransition
    }
    var changed = run
    changed.state = target
    return changed
  }
}

import Foundation

public enum ScheduleRule: Codable, Equatable, Sendable {
  case oneShot(Date)
  case daily(timeZone: String, hour: Int, minute: Int)
  case weekly(timeZone: String, hour: Int, minute: Int, weekdays: Set<Int>)
  case monthly(timeZone: String, hour: Int, minute: Int, day: Int)
  public func validate() throws {
    switch self {
    case .monthly(let zone, let hour, let minute, let day):
      try Self.validate(zone, hour, minute)
      guard (1...31).contains(day) else { throw SchedulingError.invalidValue }
    case .oneShot(let date):
      guard date.timeIntervalSince1970.isFinite else { throw SchedulingError.invalidValue }
    case .daily(let zone, let hour, let minute): try Self.validate(zone, hour, minute)
    case .weekly(let zone, let hour, let minute, let days):
      try Self.validate(zone, hour, minute)
      guard !days.isEmpty, days.allSatisfy({ (1...7).contains($0) }) else {
        throw SchedulingError.invalidValue
      }
    }
  }
  private static func validate(_ zone: String, _ hour: Int, _ minute: Int) throws {
    guard TimeZone(identifier: zone) != nil, (0...23).contains(hour), (0...59).contains(minute)
    else { throw SchedulingError.invalidValue }
  }
  public func next(after instant: Date) throws -> Date? {
    try validate()
    guard instant.timeIntervalSince1970.isFinite else { throw SchedulingError.invalidValue }
    switch self {
    case .monthly(let zone, let hour, let minute, let targetDay):
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(identifier: zone)!
      guard let interval = calendar.dateInterval(of: .month, for: instant) else {
        throw SchedulingError.invalidValue
      }
      var month = interval.start
      for _ in 0..<24 {
        if let days = calendar.range(of: .day, in: .month, for: month), days.contains(targetDay),
          let day = calendar.date(byAdding: .day, value: targetDay - 1, to: month),
          let candidate = try Self.next(
            zone: zone, hour: hour, minute: minute, weekday: nil, after: day.addingTimeInterval(-1)),
          calendar.isDate(candidate, inSameDayAs: day), candidate > instant
        {
          return candidate
        }
        guard let following = calendar.date(byAdding: .month, value: 1, to: month) else {
          return nil
        }
        month = following
      }
      throw SchedulingError.invalidValue
    case .oneShot(let date): return date > instant ? date : nil
    case .daily(let zone, let hour, let minute):
      return try Self.next(zone: zone, hour: hour, minute: minute, weekday: nil, after: instant)
    case .weekly(let zone, let hour, let minute, let days):
      return try days.compactMap {
        try Self.next(zone: zone, hour: hour, minute: minute, weekday: $0, after: instant)
      }.min()
    }
  }
  private static func next(zone: String, hour: Int, minute: Int, weekday: Int?, after instant: Date)
    throws -> Date?
  {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    var parts = DateComponents()
    parts.hour = hour
    parts.minute = minute
    parts.second = 0
    parts.weekday = weekday
    guard
      var date = calendar.nextDate(
        after: instant, matching: parts, matchingPolicy: .nextTime, repeatedTimePolicy: .first,
        direction: .forward)
    else { return nil }
    // A strict-after query following the first overlap must not execute its second
    // occurrence. Compare each candidate against the first matching instant of day.
    for _ in 0..<8 {
      let day = calendar.startOfDay(for: date)
      if let first = calendar.nextDate(
        after: day.addingTimeInterval(-1), matching: parts, matchingPolicy: .nextTime,
        repeatedTimePolicy: .first, direction: .forward), first <= instant
      {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: day),
          let following = calendar.nextDate(
            after: tomorrow.addingTimeInterval(-1), matching: parts, matchingPolicy: .nextTime,
            repeatedTimePolicy: .first, direction: .forward)
        else { return nil }
        date = following
      } else {
        return date
      }
    }
    throw SchedulingError.invalidValue
  }
}

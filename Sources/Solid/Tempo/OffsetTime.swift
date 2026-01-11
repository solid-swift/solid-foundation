//
//  OffsetTime.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//


public struct OffsetTime {

  public var time: LocalTime
  public var offset: ZoneOffset

  public var hour: Int { time.hour }
  public var minute: Int { time.minute }
  public var second: Int { time.second }
  public var nanosecond: Int { time.nanosecond }

  public init(time: LocalTime, offset: ZoneOffset) {
    self.time = time
    self.offset = offset
  }

  public init(hour: Int, minute: Int, second: Int, nanosecond: Int, offset: ZoneOffset) throws {
    self.time = try .init(hour: hour, minute: minute, second: second, nanosecond: nanosecond)
    self.offset = offset
  }

}

extension OffsetTime: Sendable {}
extension OffsetTime: Hashable {}
extension OffsetTime: Equatable {}

extension OffsetTime: Comparable {

  public static func < (lhs: Self, rhs: Self) -> Bool {
    return lhs.time < rhs.time
  }

}

extension OffsetTime: CustomStringConvertible {

  public var description: String {
    "\(time)\(offset)"
  }
}

extension OffsetTime {

  private nonisolated(unsafe) static let parseRegex =
    /^(?<hour>[01]\d|2[0-3]):(?<minute>[0-5]\d):((?<second>[0-5]\d|60)(\.(?<nanosecond>[0-9]{1,9}))?)(?<offset>Z|[+\-](?:[012]\d):[0-5]\d)$/
    .asciiOnlyDigits()
    .asciiOnlyWordCharacters()
    .ignoresCase()

  /// Parses a time with offset string per RFC-3339 (`HH:MM:SS[.sssssssss](Z|[+-]HH:MM)`).
  ///
  /// If the time string represents a time in a leap second period (e.g., `23:59:60`), the time is silently
  /// rolled over to `00:00:00.000`.
  ///
  /// - Parameter string: The full-time string.
  /// - Returns: Parsed offset time instance if valid; otherwise, nil.
  ///
  public static func parse(string: String) -> Self? {

    guard let time = parseReportingRollover(string: string)?.time else {
      return nil
    }

    return time
  }

  /// Parses a time with offset string per RFC-3339 (`HH:MM:SS[.sssssssss](Z|[+-]HH:MM)`) reporting leap second rollover.
  ///
  /// If the time string represents a time in a leap second period (e.g., `23:59:60`), the time is rolled over to
  /// `00:00:00.000` and the `rollover` flag wil lbe `true`.
  ///
  /// - Parameter string: The full-time string.
  /// - Returns: Parsed offset time and flag inidicating if leap second rollover occurred.
  ///
  public static func parseReportingRollover(string: String) -> (time: Self, rollover: Bool)? {

    guard let match = string.wholeMatch(of: parseRegex) else {
      return nil
    }

    guard
      var hour = Int(match.output.hour),
      var minute = Int(match.output.minute),
      var second = Int(match.output.second),
      let nanosecond = Int(match.output.nanosecond.map { $0.rightPad(to: 9, with: "0") } ?? "0")
    else {
      return nil
    }

    let tzOffsetStr = match.output.offset
    let tzOffset: ZoneOffset
    let zHour: Int
    let zMinute: Int
    if tzOffsetStr.caseInsensitiveCompare("Z") == .orderedSame {
      tzOffset = .zero
      zHour = hour
      zMinute = minute
    } else {
      // Parse offset in the format ±HH:MM.
      let tzSign: Int = tzOffsetStr.first == "-" ? -1 : 1
      let tzOffsetBody = tzOffsetStr.dropFirst()    // Remove the sign.
      let tzComponents = tzOffsetBody.split(separator: ":")
      guard
        tzComponents.count == 2,
        let offsetHour = Int(tzComponents[0]),
        let offsetMinute = Int(tzComponents[1]),
        let offset = try? ZoneOffset(hours: tzSign * offsetHour, minutes: tzSign * offsetMinute, seconds: 0)
      else {
        return nil
      }
      // Convert local time to UTC by applying the timezone offset
      let timeSeconds = (((hour * 3600 + minute * 60 - offset.totalSeconds) % 86400) + 86400) % 86400
      zHour = timeSeconds / 3600
      zMinute = (timeSeconds % 3600) / 60
      tzOffset = offset
    }

    // Validate seconds.
    let rolledOverLeap: Bool
    if second == 60 {
      // Leap seconds are only valid at 23:59:60
      guard zHour == 23 && zMinute == 59 else {
        return nil
      }

      rolledOverLeap = true
      hour = 0
      minute = 0
      second = 0

    } else {

      rolledOverLeap = false
    }

    guard
      let time = try? Self(hour: hour, minute: minute, second: second, nanosecond: nanosecond, offset: tzOffset)
    else {
      return nil
    }

    return (time, rolledOverLeap)
  }

}

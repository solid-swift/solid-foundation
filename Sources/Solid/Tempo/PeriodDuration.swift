//
//  PeriodDuration.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

public struct PeriodDuration {

  public var period: Period
  public var duration: Duration

  public init(period: Period, duration: Duration) {
    self.period = period
    self.duration = duration
  }

}

extension PeriodDuration: Hashable {}

extension PeriodDuration: Equatable {}

extension PeriodDuration: Sendable {}

extension PeriodDuration: CustomStringConvertible {

  public var description: String { "P\(period)T\(duration)" }

}

extension PeriodDuration {

  private nonisolated(unsafe) static let parseRegex =
    /^P(?:(?<weeks>\d+)W|(?=(?:\d+[YMD]|T(?:\d+[HMS])))(?:(?<years>\d+)Y)?(?:(?<months>\d+)M)?(?:(?<days>\d+)D)?(?:(?<time>T)(?:(?<hours>\d+)H)?(?:(?<minutes>\d+)M)?(?:(?<seconds>\d+(?:\.\d+)?)S)?)?)$/
    .asciiOnlyDigits()
    .asciiOnlyWordCharacters()

  /// Parses an ISO‑8601 duration string according to RFC-3339.
  ///
  /// Supported formats include:
  /// - Weeks: `"P4W"`
  /// - Standard form: `"P3Y6M4DT12H30M5S"`, `"PT20M"`, `"P23DT23H"`, etc.
  ///
  /// - Parameter string: The duration string to parse.
  /// - Returns: A Duration instance if the input is valid; otherwise, nil.
  public static func parse(string: String) -> PeriodDuration? {
    // This regex uses named capture groups to extract each component.
    // It has two alternatives for the date part:
    // 1. A weeks-only duration: one or more digits followed by "W".
    // 2. A standard duration with optional years, months, days, and an optional time part.
    //
    // Lookahead (?=(?:\d+[YMD]|T(?:\d+[HMS]))
    // ensures that if the weeks alternative is not taken, at least one designator is present.

    guard let match = string.wholeMatch(of: parseRegex) else {
      return nil
    }

    let output = match.output

    // If a weeks component is provided, that is the sole date field.
    let period: Period?
    if let weeksStr = output.weeks {
      period = Period(weeks: Int(weeksStr) ?? 0)
    } else {
      let years: Int? =
        if let yearsStr = output.years {
          Int(yearsStr)
        } else {
          nil
        }
      let months: Int? =
        if let monthsStr = output.months {
          Int(monthsStr)
        } else {
          nil
        }
      let days: Int? =
        if let daysStr = output.days {
          Int(daysStr)
        } else {
          nil
        }

      period =
        if years != nil || months != nil || days != nil {
          // If any date component is provided, create a Period instance.
          Period(years: years ?? 0, months: months ?? 0, days: days ?? 0)
        } else {
          nil
        }
    }


    let duration: Duration?
    if output.time != nil {
      var hours: Int?
      if let hoursStr = output.hours {
        hours = Int(hoursStr) ?? 0
      }
      var minutes: Int?
      if let minutesStr = output.minutes {
        minutes = Int(minutesStr) ?? 0
      }
      var seconds: Int?
      var nanoseconds: Int?
      if let secondsStr = output.seconds {
        let secondsParts = secondsStr.split(separator: ".", maxSplits: 2)
        if secondsParts.count == 2 {
          seconds = Int(secondsParts[0])
          nanoseconds = Int(secondsParts[1])
        } else {
          seconds = Int(secondsParts[0])
        }
      }

      // If any time component is provided, create a Duration instance.
      guard hours != nil || minutes != nil || seconds != nil else {
        // If all time components are missing (except the seperator), the duration is invalid.
        return nil
      }
      duration = .hours(hours ?? 0) + .minutes(minutes ?? 0) + .seconds(seconds ?? 0) + .nanoseconds(nanoseconds ?? 0)
    } else {
      duration = nil
    }

    return Self(period: period ?? .zero, duration: duration ?? .zero)
  }


}

//
//  IntegerTimeArgument.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/29/25.
//

import Foundation


public struct IntegerTimeLogArgument<I: FixedWidthInteger & Sendable>: LogArgument {

  public enum Format: Sendable {
    case `default`
    case units(Duration.UnitsFormatStyle)
    case time(Duration.TimeFormatStyle)
  }

  public enum Unit: Sendable {
    case seconds
    case milliseconds
    case microseconds
    case nanoseconds
  }

  public var int: @Sendable () -> I
  public var unit: Unit
  public var format: Format
  public var privacy: LogPrivacy

  public init(int: @escaping @Sendable () -> I, unit: Unit, format: Format, privacy: LogPrivacy? = nil) {
    self.int = int
    self.unit = unit
    self.format = format
    self.privacy = privacy ?? .public
  }

  private let constantFormatStyle = ConstantFormatStyles.for(I.self)

  public var constantValue: String {
    int().formatted(constantFormatStyle)
  }

  public var formattedValue: String {
    let value = unit.apply(int())
    return format.format(value)
  }

}


extension IntegerTimeLogArgument.Format {

  func format(_ value: Duration) -> String {
    switch self {
    case .default:
      value.formatted()
    case .units(let unitsFormatStyle):
      unitsFormatStyle.format(value)
    case .time(let timeFormatStyle):
      timeFormatStyle.format(value)
    }
  }

}


extension IntegerTimeLogArgument.Unit {

  func apply(_ value: I) -> Duration {
    switch self {
    case .seconds:
      return .seconds(value)
    case .milliseconds:
      return .milliseconds(value)
    case .microseconds:
      return .microseconds(value)
    case .nanoseconds:
      return .nanoseconds(value)
    }
  }

}

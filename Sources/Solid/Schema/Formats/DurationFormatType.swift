//
//  DurationFormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData
import SolidTempo


/// RFC 3339 duration format type.
public enum DurationFormatType: Schema.FormatType {
  case instance

  public var identifier: String { "duration" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let value) = value else { return false }
    return PeriodDuration.parse(string: value) != nil
  }
}

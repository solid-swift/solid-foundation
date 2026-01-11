//
//  TimeFormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData
import SolidTempo


/// RFC 3339 time format type.
public enum TimeFormatType: Schema.FormatType {
  case instance

  public var identifier: String { "time" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let string) = value else { return false }
    return OffsetTime.parse(string: string) != nil
  }
}

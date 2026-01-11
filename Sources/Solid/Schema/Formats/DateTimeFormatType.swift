//
//  DateTimeFormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData
import SolidTempo


/// RFC 3339 date-time format type.
public enum DateTimeFormatType: Schema.FormatType {
  case instance

  public var identifier: String { "date-time" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let string) = value else { return false }
    return OffsetDateTime.parse(string: string) != nil
  }
}

//
//  DateFormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData
import SolidTempo


/// RFC 3339 date format type.
public enum DateFormatType: Schema.FormatType {
  case instance

  public var identifier: String { "date" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let string) = value else { return false }
    return LocalDate.parse(string: string) != nil
  }
}

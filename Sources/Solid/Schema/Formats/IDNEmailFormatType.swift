//
//  IDNEmailFormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData
import SolidNet


/// RFC 6531 IDN email format type.
public enum IDNEmailFormatType: Schema.FormatType {
  case instance

  public var identifier: String { "idn-email" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let value) = value else { return false }
    return IDNEmailAddress.parse(string: value) != nil
  }
}

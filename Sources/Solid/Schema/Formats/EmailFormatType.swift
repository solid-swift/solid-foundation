//
//  EmailFormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData
import SolidNet


/// RFC 5321 email format type.
public enum EmailFormatType: Schema.FormatType {
  case instance

  public var identifier: String { "email" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let value) = value else { return false }
    return EmailAddress.parse(string: value) != nil
  }
}

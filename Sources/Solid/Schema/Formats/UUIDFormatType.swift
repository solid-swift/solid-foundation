//
//  UUIDFormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidCore
import SolidData
import SolidID


/// UUID format type.
public enum UUIDFormatType: Schema.FormatType {
  case instance

  public var identifier: String { "uuid" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let string) = value else { return false }
    return UUID(string: string, using: .canonical) != nil
  }
}

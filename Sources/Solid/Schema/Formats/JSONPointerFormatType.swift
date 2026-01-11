//
//  JSONPointerFormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData


/// JSON Pointer format type.
public enum JSONPointerFormatType: Schema.FormatType {
  case instance

  public var identifier: String { "json-pointer" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let string) = value else { return false }
    return Pointer(encoded: string) != nil
  }
}

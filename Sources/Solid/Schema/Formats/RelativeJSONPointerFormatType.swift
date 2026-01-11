//
//  RelativeJSONPointerFormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData


/// Relative JSON Pointer format type.
public enum RelativeJSONPointerFormatType: Schema.FormatType {
  case instance

  public var identifier: String { "relative-json-pointer" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let string) = value else { return false }
    return RelativePointer(encoded: string) != nil
  }
}

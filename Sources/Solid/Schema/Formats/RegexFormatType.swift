//
//  RegexFormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData


/// Regular expression format type.
public enum RegexFormatType: Schema.FormatType {
  case instance

  public var identifier: String { "regex" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let string) = value else { return false }
    do {
      _ = try Regex(string)
      return true
    } catch {
      return false
    }
  }
}

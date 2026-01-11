//
//  IPv6FormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData
import SolidNet


/// RFC 4291 IPv6 address format type.
public enum IPv6FormatType: Schema.FormatType {
  case instance

  public var identifier: String { "ipv6" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let string) = value else { return false }
    return IPv6Address.parse(string: string) != nil
  }
}

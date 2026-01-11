//
//  IPv4FormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData
import SolidNet


/// RFC 2673 IPv4 address format type.
public enum IPv4FormatType: Schema.FormatType {
  case instance

  public var identifier: String { "ipv4" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let string) = value else { return false }
    return IPv4Address.parse(string: string) != nil
  }
}

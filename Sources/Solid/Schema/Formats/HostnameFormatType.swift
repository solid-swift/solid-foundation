//
//  HostnameFormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData
import SolidNet


/// RFC 1123 hostname format type.
public enum HostnameFormatType: Schema.FormatType {
  case instance

  public var identifier: String { "hostname" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let string) = value else { return false }
    return Hostname.parse(string: string) != nil
  }
}

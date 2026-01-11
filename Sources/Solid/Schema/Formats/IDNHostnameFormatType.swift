//
//  IDNHostnameFormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData
import SolidNet


/// RFC 5890 IDN hostname format type.
public enum IDNHostnameFormatType: Schema.FormatType {
  case instance

  public var identifier: String { "idn-hostname" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let string) = value else { return false }
    return IDNHostname.parse(string: string) != nil
  }
}

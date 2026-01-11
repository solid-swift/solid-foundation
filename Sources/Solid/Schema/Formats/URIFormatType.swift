//
//  URIFormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData
import SolidURI


/// RFC 3986 URI format type.
public enum URIFormatType: Schema.FormatType {
  case instance

  public var identifier: String { "uri" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let string) = value else { return false }
    return URI(encoded: string, requirements: .uri) != nil
  }
}

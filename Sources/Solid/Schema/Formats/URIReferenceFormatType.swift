//
//  URIReferenceFormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData
import SolidURI


/// RFC 3986 URI reference format type.
public enum URIReferenceFormatType: Schema.FormatType {
  case instance

  public var identifier: String { "uri-reference" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let string) = value else { return false }
    return URI(encoded: string, requirements: .uriReference) != nil
  }
}

//
//  IRIReferenceFormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData
import SolidURI


/// RFC 3987 IRI reference format type.
public enum IRIReferenceFormatType: Schema.FormatType {
  case instance

  public var identifier: String { "iri-reference" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let string) = value else { return false }
    return URI(encoded: string, requirements: .iriReference) != nil
  }
}

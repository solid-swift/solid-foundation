//
//  URITemplateFormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData
import SolidURI


/// RFC 6570 URI template format type.
public enum URITemplateFormatType: Schema.FormatType {
  case instance

  public var identifier: String { "uri-template" }

  public func validate(_ value: Value) -> Bool {
    guard case .string(let string) = value else { return false }
    return URI.Template.parse(string).value != nil
  }
}

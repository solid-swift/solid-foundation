//
//  UnknownFormatType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData


public enum UnknownFormatType: Schema.FormatType {
  case instance

  public var identifier: String { "" }

  public func validate(_ value: Value) -> Bool {
    return true
  }

}

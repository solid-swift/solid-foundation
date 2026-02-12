//
//  YAMLValueDocument.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData

/// Value-based YAML document with explicit marker metadata.
public struct YAMLValueDocument: Sendable, Equatable {
  public var value: Value
  public var explicitStart: Bool
  public var explicitEnd: Bool

  public init(value: Value, explicitStart: Bool = false, explicitEnd: Bool = false) {
    self.value = value
    self.explicitStart = explicitStart
    self.explicitEnd = explicitEnd
  }
}

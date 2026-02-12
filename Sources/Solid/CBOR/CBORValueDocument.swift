//
//  CBORValueDocument.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/18/26.
//

import SolidData

/// A CBOR document represented as a single ``Value``.
public struct CBORValueDocument: Sendable, Equatable {

  public let value: Value

  public init(value: Value) {
    self.value = value
  }
}

//
//  EmitEventDecoder.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import Foundation

/// Decodes a stream of ``EmitEvent`` values into a single ``Value``.
///
/// Delegates all container-tracking logic to ``ParseEventDecoder`` by converting
/// each ``EmitEvent`` to a ``ParseEvent`` via ``ParseEvent/init(from:)``.
/// Because every ``EmitEvent`` scalar is already a materialised ``Value``,
/// no ``ScalarResolver`` is needed.
public struct EmitEventDecoder {

  public enum Error: Swift.Error {
    case invalidEventSequence(String)
    case incompleteValue
  }

  private var inner: ParseEventDecoder

  public init() {
    self.inner = ParseEventDecoder()
  }

  public var isComplete: Bool { inner.isComplete }

  public mutating func append(_ event: EmitEvent) throws {
    do {
      try inner.append(ParseEvent(from: event))
    } catch let e as ParseEventDecoder.Error {
      throw mapError(e)
    }
  }

  public mutating func finish() throws -> Value {
    do {
      return try inner.finish()
    } catch let e as ParseEventDecoder.Error {
      throw mapError(e)
    }
  }

  private func mapError(_ error: ParseEventDecoder.Error) -> Error {
    switch error {
    case .invalidEventSequence(let message):
      return .invalidEventSequence(message)
    case .incompleteValue:
      return .incompleteValue
    }
  }
}

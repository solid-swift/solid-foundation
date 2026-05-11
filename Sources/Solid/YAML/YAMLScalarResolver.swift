//
//  YAMLScalarResolver.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 3/22/26.
//

import Foundation
import SolidData

/// Scalar resolver for YAML format.
///
/// Handles deferred materialisation of lazy ``ScalarRef`` values emitted by
/// the YAML event reader/tokenizer pipeline.
///
/// Plain scalars without an explicit tag are emitted with ``ScalarRef/Kind/number``
/// and backed by a ``ParseBuffer/Region`` containing the raw UTF-8 text.  When
/// ``resolve(_:kind:)`` is called for that kind, it performs full YAML 1.2
/// implicit-type inference — the same logic as ``YAMLTagResolver/resolveImplicit(_:)``:
/// null → bool → number → string.
///
/// All other kinds (`.null`, `.bool`, `.string`, `.bytes`) are straightforward
/// and are handled without re-parsing.
public struct YAMLScalarResolver: RegionScalarResolver, Sendable {

  public init() {}

  public func resolve(_ data: Data, kind: ScalarRef.Kind) throws -> Value {
    switch kind {
    case .null:
      return .null

    case .bool(let b):
      return .bool(b)

    case .string:
      guard let string = String(data: data, encoding: .utf8) else {
        throw YAML.ParseError.invalidSyntax("Invalid UTF-8 string", location: nil)
      }
      return .string(string)

    case .integer, .float, .number:
      // `.number` is used for lazy plain YAML scalars (no explicit tag).
      // Apply full YAML 1.2 implicit type inference via YAMLTagResolver.
      guard let text = String(data: data, encoding: .utf8) else {
        throw YAML.ParseError.invalidSyntax("Invalid scalar text", location: nil)
      }
      let scalar = YAMLScalar(text: text, style: .plain)
      return YAMLTagResolver().resolve(scalar, explicitTag: nil, wrapTag: false)

    case .bytes:
      return .bytes(data)
    }
  }

  public func resolve(_ region: ParseBuffer.Region, kind: ScalarRef.Kind) throws -> Value {
    switch kind {
    case .string:
      do {
        return .string(try region.string())
      } catch ParseBufferError.invalidUTF8 {
        throw YAML.ParseError.invalidSyntax("Invalid UTF-8 string", location: nil)
      }

    case .integer, .float, .number:
      let text: String
      do {
        text = try region.string()
      } catch ParseBufferError.invalidUTF8 {
        throw YAML.ParseError.invalidSyntax("Invalid scalar text", location: nil)
      }
      let scalar = YAMLScalar(text: text, style: .plain)
      return YAMLTagResolver().resolve(scalar, explicitTag: nil, wrapTag: false)

    default:
      return try resolve(region.bytes, kind: kind)
    }
  }
}

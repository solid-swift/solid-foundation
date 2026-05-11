//
//  ScalarRef.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 3/21/26.
//

import Foundation

/// A zero-copy scalar reference that defers materialization until requested.
///
/// `ScalarRef` carries either a buffer region (zero-copy reference into the parser's
/// input buffer) or a pre-materialized `Value`. Buffered values are resolved on demand;
/// callers that revisit the same scalar should cache materialized values at the
/// decoder or application layer.
public struct ScalarRef: Sendable {

  /// The kind of scalar, known without materialization.
  public enum Kind: Sendable, Equatable {
    /// The null value.
    case null
    /// A boolean value (already decoded).
    case bool(Bool)
    /// An integer in text (JSON) or binary (CBOR) form.
    case integer
    /// A floating-point number in text (JSON) or binary (CBOR) form.
    case float
    /// A string — raw UTF-8 (CBOR/YAML) or JSON-escaped (escapes NOT processed).
    case string
    /// Raw bytes (CBOR byte strings).
    case bytes
    /// A general number in text form (YAML resolved numbers).
    case number
  }

  /// The kind of scalar, available without materialization.
  public let kind: Kind

  private let storage: Storage

  /// Create a scalar reference backed by a buffer region.
  public init(kind: Kind, region: ParseBuffer.Region) {
    self.kind = kind
    self.storage = .buffered(region)
  }

  /// Create a scalar reference with a pre-materialized value.
  public init(kind: Kind, value: Value) {
    self.kind = kind
    self.storage = .materialized(value)
  }

  /// Convenience initializer for null.
  public static let null = ScalarRef(kind: .null, value: .null)

  /// Convenience initializer for booleans.
  public static func bool(_ value: Bool) -> ScalarRef {
    ScalarRef(kind: .bool(value), value: .bool(value))
  }

  /// Create a ScalarRef from a pre-materialized Value, inferring the kind.
  ///
  /// The resolver is never called for pre-materialized values.
  public static func materialized(_ value: Value) -> ScalarRef {
    switch value {
    case .null: return .null
    case .bool(let b): return .bool(b)
    case .number: return ScalarRef(kind: .number, value: value)
    case .string: return ScalarRef(kind: .string, value: value)
    case .bytes: return ScalarRef(kind: .bytes, value: value)
    default: return ScalarRef(kind: .string, value: value)
    }
  }

  // MARK: - Zero-cost convenience (no materialization needed)

  /// Whether this scalar is null, without materialization.
  public var isNull: Bool { kind == .null }

  /// The boolean value if this scalar is a boolean, without materialization.
  ///
  /// Returns `nil` for non-boolean scalars.
  public var boolValue: Bool? {
    if case .bool(let b) = kind { return b }
    return nil
  }

  // MARK: - Raw data access

  /// Access the raw bytes of this scalar without materialization.
  ///
  /// Returns `nil` for pre-materialized values.
  public var rawData: Data? {
    if case .buffered(let region) = storage {
      return region.bytes
    }
    return nil
  }

  // MARK: - Materialization

  /// Materialize this scalar into a `Value`.
  ///
  /// For buffered storage, the provided resolver performs format-specific decoding
  /// (string unescaping, number parsing, etc.). Buffered storage does not cache;
  /// callers that need repeated materialization should cache the returned value.
  ///
  /// For pre-materialized storage, returns the value directly.
  public func materialize(using resolver: some ScalarResolver) throws -> Value {
    switch storage {
    case .materialized(let value):
      return value
    case .buffered(let region):
      if let regionResolver = resolver as? any RegionScalarResolver {
        return try regionResolver.resolve(region, kind: kind)
      }
      return try resolver.resolve(region.bytes, kind: kind)
    }
  }
}

/// Protocol for format-specific scalar materialization.
///
/// Each format provides its own resolver that knows how to decode
/// buffer regions into `Value` objects.
public protocol ScalarResolver: Sendable {
  func resolve(_ data: Data, kind: ScalarRef.Kind) throws -> Value
}

/// Optional resolver refinement for implementations that can decode directly
/// from a retained ``ParseBuffer/Region``.
public protocol RegionScalarResolver: ScalarResolver {
  func resolve(_ region: ParseBuffer.Region, kind: ScalarRef.Kind) throws -> Value
}

// MARK: - Internal storage

private enum Storage: Sendable {
  case buffered(ParseBuffer.Region)
  case materialized(Value)
}

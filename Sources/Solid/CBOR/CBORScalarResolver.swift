//
//  CBORScalarResolver.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 3/22/26.
//

import Foundation
import SolidData
import SolidNumeric

/// Scalar resolver for CBOR values.
///
/// Decodes buffered CBOR scalar regions into ``Value`` objects:
/// - **Integers**: Decodes init byte + big-endian magnitude bytes (positive and negative)
/// - **Floats**: Decodes init byte + IEEE 754 bytes (half/single/double precision)
/// - **Strings**: Validates UTF-8 payload bytes
/// - **Byte strings**: Wraps raw payload bytes
public struct CBORScalarResolver: RegionScalarResolver {

  public init() {}

  public func resolve(_ data: Data, kind: ScalarRef.Kind) throws -> Value {
    switch kind {
    case .null:
      return .null
    case .bool(let b):
      return .bool(b)
    case .string:
      guard let string = String(data: data, encoding: .utf8) else {
        throw CBOR.Error.invalidUTF8String
      }
      return .string(string)
    case .bytes:
      return .bytes(data)
    case .integer:
      return try resolveInteger(data)
    case .float:
      return try resolveFloat(data)
    case .number:
      preconditionFailure("CBOR does not produce .number kind scalars")
    }
  }

  public func resolve(_ region: ParseBuffer.Region, kind: ScalarRef.Kind) throws -> Value {
    switch kind {
    case .string:
      do {
        return .string(try region.string())
      } catch ParseBufferError.invalidUTF8 {
        throw CBOR.Error.invalidUTF8String
      }
    case .bytes:
      return .bytes(region.bytes)
    case .integer:
      return try region.withUnsafeBytes { rawBuffer in
        try resolveInteger(rawBuffer)
      }
    case .float:
      return try region.withUnsafeBytes { rawBuffer in
        try resolveFloat(rawBuffer)
      }
    default:
      return try resolve(region.bytes, kind: kind)
    }
  }

  // MARK: - Integer resolution

  /// Decode a CBOR integer from its raw bytes (init byte + magnitude).
  ///
  /// The region contains the complete CBOR encoding:
  /// - Byte 0: init byte (major type in top 3 bits, additional info in lower 5 bits)
  /// - Bytes 1+: big-endian magnitude (0, 1, 2, 4, or 8 bytes depending on additional info)
  private func resolveInteger(_ data: Data) throws -> Value {
    try data.withUnsafeBytes { rawBuffer in
      try resolveInteger(rawBuffer)
    }
  }

  private func resolveInteger(_ rawBuffer: UnsafeRawBufferPointer) throws -> Value {
    guard rawBuffer.count >= 1 else {
      throw CBOR.Error.invalidItemType
    }

    let initByte = rawBuffer[0]
    let majorType = initByte & 0xE0
    let additionalInfo = initByte & 0x1F

    let magnitude: UInt64
    if additionalInfo <= 0x17 {
      // Inline value (0-23)
      magnitude = UInt64(additionalInfo)
    } else {
      switch additionalInfo {
      case 0x18:
        guard rawBuffer.count >= 2 else { throw CBOR.Error.unexpectedEndOfStream }
        magnitude = UInt64(rawBuffer[1])
      case 0x19:
        guard rawBuffer.count >= 3 else { throw CBOR.Error.unexpectedEndOfStream }
        magnitude = UInt64(UInt16(bigEndian: rawBuffer.loadUnaligned(fromByteOffset: 1, as: UInt16.self)))
      case 0x1A:
        guard rawBuffer.count >= 5 else { throw CBOR.Error.unexpectedEndOfStream }
        magnitude = UInt64(UInt32(bigEndian: rawBuffer.loadUnaligned(fromByteOffset: 1, as: UInt32.self)))
      case 0x1B:
        guard rawBuffer.count >= 9 else { throw CBOR.Error.unexpectedEndOfStream }
        magnitude = UInt64(bigEndian: rawBuffer.loadUnaligned(fromByteOffset: 1, as: UInt64.self))
      default:
        throw CBOR.Error.invalidItemType
      }
    }

    switch majorType {
    case 0x00:
      // Positive integer (major type 0)
      return .number(magnitude)
    case 0x20:
      // Negative integer (major type 1): value = -1 - magnitude
      if magnitude <= UInt64(Int64.max) {
        return .number(-1 - Int64(magnitude))
      } else {
        return .number(-(BigInt(magnitude) + 1))
      }
    default:
      throw CBOR.Error.invalidItemType
    }
  }

  // MARK: - Float resolution

  /// Decode a CBOR float from its raw bytes (init byte + IEEE 754 payload).
  ///
  /// The region contains:
  /// - Byte 0: init byte (0xF9 = half, 0xFA = single, 0xFB = double)
  /// - Bytes 1+: big-endian IEEE 754 bits (2, 4, or 8 bytes)
  private func resolveFloat(_ data: Data) throws -> Value {
    try data.withUnsafeBytes { rawBuffer in
      try resolveFloat(rawBuffer)
    }
  }

  private func resolveFloat(_ rawBuffer: UnsafeRawBufferPointer) throws -> Value {
    guard rawBuffer.count >= 1 else {
      throw CBOR.Error.invalidItemType
    }

    let initByte = rawBuffer[0]
    switch initByte {
    case 0xF9:
      guard rawBuffer.count >= 3 else { throw CBOR.Error.unexpectedEndOfStream }
      let bits = UInt16(bigEndian: rawBuffer.loadUnaligned(fromByteOffset: 1, as: UInt16.self))
      return .number(Float16(bitPattern: bits))

    case 0xFA:
      guard rawBuffer.count >= 5 else { throw CBOR.Error.unexpectedEndOfStream }
      let bits = UInt32(bigEndian: rawBuffer.loadUnaligned(fromByteOffset: 1, as: UInt32.self))
      return .number(Float32(bitPattern: bits))

    case 0xFB:
      guard rawBuffer.count >= 9 else { throw CBOR.Error.unexpectedEndOfStream }
      let bits = UInt64(bigEndian: rawBuffer.loadUnaligned(fromByteOffset: 1, as: UInt64.self))
      return .number(Float64(bitPattern: bits))

    default:
      throw CBOR.Error.invalidItemType
    }
  }
}

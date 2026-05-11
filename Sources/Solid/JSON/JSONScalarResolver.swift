//
//  JSONScalarResolver.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 3/21/26.
//

import Foundation
import SolidData

/// Resolves raw JSON scalar bytes into ``Value`` instances.
///
/// Handles deferred string unescaping (including surrogate pair reassembly)
/// and number parsing (fast-path integer, fallback to TextNumber/BigDecimal).
public struct JSONScalarResolver: RegionScalarResolver {

  public init() {}

  public func resolve(_ data: Data, kind: ScalarRef.Kind) throws -> Value {
    switch kind {
    case .null:
      return .null
    case .bool(let b):
      return .bool(b)
    case .string:
      return .string(try resolveString(data))
    case .integer:
      return try resolveInteger(data)
    case .float, .number:
      return try resolveNumber(data)
    case .bytes:
      return .bytes(data)
    }
  }

  public func resolve(_ region: ParseBuffer.Region, kind: ScalarRef.Kind) throws -> Value {
    switch kind {
    case .string:
      if !containsBackslash(region) {
        return .string(try decodeUTF8(region))
      }
      return .string(try resolveString(region))
    case .integer:
      return try resolveInteger(region)
    case .float, .number:
      return try resolveNumber(region)
    default:
      return try resolve(region.bytes, kind: kind)
    }
  }

  // MARK: - String Resolution

  private func containsBackslash(_ region: ParseBuffer.Region) -> Bool {
    region.withUnsafeBytes { rawBuffer in
      for byte in rawBuffer where byte == UInt8(ascii: "\\") {
        return true
      }
      return false
    }
  }

  private func decodeUTF8(_ region: ParseBuffer.Region) throws -> String {
    try region.withUnsafeBytes { rawBuffer in
      try decodeUTF8(rawBuffer)
    }
  }

  private func decodeUTF8(_ rawBuffer: UnsafeRawBufferPointer) throws -> String {
    let utf8 = rawBuffer.bindMemory(to: UInt8.self)
    guard let string = String(bytes: utf8, encoding: .utf8) else {
      throw JSON.Error.invalidUTF8String
    }
    return string
  }

  private func decodeUTF8(_ bytes: ContiguousArray<UInt8>) throws -> String {
    try bytes.withUnsafeBufferPointer { buffer in
      guard let string = String(bytes: buffer, encoding: .utf8) else {
        throw JSON.Error.invalidUTF8String
      }
      return string
    }
  }

  /// Process JSON escape sequences in raw string bytes.
  ///
  /// Input is the raw bytes between the opening and closing quotes,
  /// with escape sequences still present (e.g., `\n`, `\uXXXX`).
  private func resolveString(_ data: Data) throws -> String {
    try data.withUnsafeBytes { rawBuffer in
      try resolveString(rawBuffer)
    }
  }

  private func resolveString(_ region: ParseBuffer.Region) throws -> String {
    try region.withUnsafeBytes { rawBuffer in
      try resolveString(rawBuffer)
    }
  }

  private func resolveString(_ rawBuffer: UnsafeRawBufferPointer) throws -> String {
    let data = rawBuffer.bindMemory(to: UInt8.self)
    var output = ContiguousArray<UInt8>()
    output.reserveCapacity(data.count)

    var i = data.startIndex
    let end = data.endIndex

    while i < end {
      let byte = data[i]

      if byte == UInt8(ascii: "\\") {
        i += 1
        guard i < end else {
          throw JSON.Error.invalidEscapeSequence
        }
        let escaped = data[i]
        i += 1

        switch escaped {
        case UInt8(ascii: "\""): output.append(UInt8(ascii: "\""))
        case UInt8(ascii: "\\"): output.append(UInt8(ascii: "\\"))
        case UInt8(ascii: "/"): output.append(UInt8(ascii: "/"))
        case UInt8(ascii: "b"): output.append(0x08)
        case UInt8(ascii: "f"): output.append(0x0C)
        case UInt8(ascii: "n"): output.append(0x0A)
        case UInt8(ascii: "r"): output.append(0x0D)
        case UInt8(ascii: "t"): output.append(0x09)
        case UInt8(ascii: "u"):
          // Parse \uXXXX (and possible surrogate pair)
          let codeUnit = try parseHex4(data, at: &i)

          if isHighSurrogate(codeUnit) {
            // Expect \uXXXX for low surrogate
            guard i + 1 < end,
                  data[i] == UInt8(ascii: "\\"),
                  data[i + 1] == UInt8(ascii: "u")
            else {
              throw JSON.Error.invalidEscapeSequence
            }
            i += 2 // skip \u
            let lowUnit = try parseHex4(data, at: &i)
            guard isLowSurrogate(lowUnit) else {
              throw JSON.Error.invalidEscapeSequence
            }
            let scalar = try decodeSurrogatePair(high: codeUnit, low: lowUnit)
            appendScalar(scalar, to: &output)
          } else if isLowSurrogate(codeUnit) {
            throw JSON.Error.invalidEscapeSequence
          } else {
            guard let scalar = UnicodeScalar(codeUnit) else {
              throw JSON.Error.invalidEscapeSequence
            }
            appendScalar(scalar, to: &output)
          }

        default:
          throw JSON.Error.invalidEscapeSequence
        }
      } else {
        output.append(byte)
        i += 1
      }
    }

    return try decodeUTF8(output)
  }

  private func parseHex4(_ data: UnsafeBufferPointer<UInt8>, at i: inout Int) throws -> UInt16 {
    var value: UInt16 = 0
    for _ in 0..<4 {
      guard i < data.endIndex else {
        throw JSON.Error.invalidEscapeSequence
      }
      guard let digit = hexValue(data[i]) else {
        throw JSON.Error.invalidEscapeSequence
      }
      value = (value << 4) | digit
      i += 1
    }
    return value
  }

  private func hexValue(_ byte: UInt8) -> UInt16? {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"):
      return UInt16(byte - UInt8(ascii: "0"))
    case UInt8(ascii: "a")...UInt8(ascii: "f"):
      return UInt16(byte - UInt8(ascii: "a") + 10)
    case UInt8(ascii: "A")...UInt8(ascii: "F"):
      return UInt16(byte - UInt8(ascii: "A") + 10)
    default:
      return nil
    }
  }

  private func isHighSurrogate(_ value: UInt16) -> Bool {
    value >= 0xD800 && value <= 0xDBFF
  }

  private func isLowSurrogate(_ value: UInt16) -> Bool {
    value >= 0xDC00 && value <= 0xDFFF
  }

  private func decodeSurrogatePair(high: UInt16, low: UInt16) throws -> UnicodeScalar {
    let highValue = UInt32(high) - 0xD800
    let lowValue = UInt32(low) - 0xDC00
    let scalarValue = 0x10000 + ((highValue << 10) | lowValue)
    guard let scalar = UnicodeScalar(scalarValue) else {
      throw JSON.Error.invalidEscapeSequence
    }
    return scalar
  }

  private func appendScalar(_ scalar: UnicodeScalar, to output: inout ContiguousArray<UInt8>) {
    for byte in String(scalar).utf8 {
      output.append(byte)
    }
  }

  // MARK: - Number Resolution

  /// Fast-path integer parsing: Int64/UInt64 directly, fallback to TextNumber.
  private func resolveInteger(_ data: Data) throws -> Value {
    try data.withUnsafeBytes { rawBuffer in
      let utf8 = rawBuffer.bindMemory(to: UInt8.self)
      return try resolveIntegerBytes(utf8) {
        try resolveNumber(data)
      }
    }
  }

  private func resolveInteger(_ region: ParseBuffer.Region) throws -> Value {
    try region.withUnsafeBytes { rawBuffer in
      let utf8 = rawBuffer.bindMemory(to: UInt8.self)
      return try resolveIntegerBytes(utf8) {
        try resolveNumber(region)
      }
    }
  }

  private func resolveIntegerBytes(
    _ utf8: UnsafeBufferPointer<UInt8>,
    fallback: () throws -> Value
  ) throws -> Value {
    guard !utf8.isEmpty else { return try fallback() }

    var idx = utf8.startIndex
    let isNeg = utf8[idx] == UInt8(ascii: "-")
    if isNeg { utf8.formIndex(after: &idx) }
    guard idx < utf8.endIndex else { return try fallback() }

    var magnitude: UInt64 = 0
    var overflow = false
    while idx < utf8.endIndex {
      let byte = utf8[idx]
      guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else {
        return try fallback()
      }
      let digit = byte - UInt8(ascii: "0")
      let (m1, o1) = magnitude.multipliedReportingOverflow(by: 10)
      let (m2, o2) = m1.addingReportingOverflow(UInt64(digit))
      if o1 || o2 { overflow = true; break }
      magnitude = m2
      utf8.formIndex(after: &idx)
    }

    if !overflow {
      if isNeg {
        if magnitude <= UInt64(Int64.max) + 1 {
          return .number(.binary(.int64(Int64(bitPattern: 0 &- magnitude))))
        }
      } else {
        if magnitude <= UInt64(Int64.max) {
          return .number(.binary(.int64(Int64(magnitude))))
        } else {
          return .number(.binary(.uint64(magnitude)))
        }
      }
    }

    return try fallback()
  }

  /// Fallback number parsing via TextNumber/BigDecimal.
  private func resolveNumber(_ data: Data) throws -> Value {
    let text = String(decoding: data, as: UTF8.self)
    guard let textNumber = Value.TextNumber(text: text) else {
      throw JSON.Error.invalidNumber
    }
    return .number(.text(textNumber))
  }

  private func resolveNumber(_ region: ParseBuffer.Region) throws -> Value {
    let text = region.withUnsafeBytes { rawBuffer in
      String(decoding: rawBuffer.bindMemory(to: UInt8.self), as: UTF8.self)
    }
    guard let textNumber = Value.TextNumber(text: text) else {
      throw JSON.Error.invalidNumber
    }
    return .number(.text(textNumber))
  }
}

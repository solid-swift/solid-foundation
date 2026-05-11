//
//  CBOREventReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 3/22/26.
//

import Foundation
import SolidData
import SolidNumeric

/// A push parser for CBOR that produces ``ParseEvent`` values.
///
/// Implements ``FormatEventReader`` by reading CBOR-encoded bytes incrementally
/// and emitting structural and scalar events. Map keys are emitted as normal
/// event sequences (no recursive decoding) — the consumer tracks key/value
/// alternation via ``ParseEventDecoder``.
public struct CBOREventReader: ~Copyable, FormatEventReader, Sendable {

  private enum VarUIntSize: UInt8 {
    case uint8 = 0
    case uint16 = 1
    case uint32 = 2
    case uint64 = 3

    static func from(serialized value: UInt8) throws -> VarUIntSize {
      switch value & 0b11 {
      case 0: return .uint8
      case 1: return .uint16
      case 2: return .uint32
      case 3: return .uint64
      default:
        throw CBOR.Error.invalidIntegerSize
      }
    }
  }

  // MARK: - State

  private var buffer = ParseBuffer()
  private var finalReceived = false
  private var containers = ContainerStack()
  private var _isFinished = false
  /// Set after a root-level value completes. Causes the next `readEvent()` to
  /// return nil (pausing between root values), then auto-resets so subsequent
  /// calls can parse the next root value (multi-document support).
  private var completedRootValue = false
  private let options: CBORValueReader.Options
  private let _resolver = CBORScalarResolver()

  // MARK: - FormatEventReader

  public init(options: CBORValueReader.Options = CBORValueReader.Options()) {
    self.options = options
  }

  public var format: Format { CBOR.format }
  public var scalarResolver: any ScalarResolver { _resolver }
  public var isFinished: Bool { _isFinished }

  public mutating func feedInput(_ data: consuming Data, isFinal: Bool) {
    if !data.isEmpty {
      buffer.append(data)
    }
    if isFinal {
      finalReceived = true
    }
  }

  public mutating func readEvent() throws -> ParseEvent? {
    guard !_isFinished else { return nil }

    // Pause between root values: return nil once, then reset so the
    // next call can parse the following root value (multi-document).
    if completedRootValue {
      completedRootValue = false
      // If there's no more data and we received final, we're done.
      if buffer.isEmpty && finalReceived {
        _isFinished = true
      }
      return nil
    }

    // Check if a definite-length container has completed
    if let completion = try emitCompletedContainerIfNeeded() {
      return completion
    }

    // Check for break byte (indefinite-length container end)
    if let breakEvent = try emitBreakIfNeeded() {
      return breakEvent
    }

    // Need at least one byte to continue
    guard !buffer.isEmpty else {
      if finalReceived {
        if !containers.isEmpty {
          throw CBOR.Error.unexpectedEndOfStream
        }
        _isFinished = true
      }
      return nil
    }

    // Save position for rollback on incomplete reads
    let savedPosition = buffer.mark()

    do {
      return try parseNextItem()
    } catch CBOR.Error.unexpectedEndOfStream {
      // Rollback and wait for more data
      buffer.restore(savedPosition)
      if finalReceived {
        throw CBOR.Error.unexpectedEndOfStream
      }
      return nil
    }
  }

  // MARK: - Item parsing

  private mutating func parseNextItem() throws -> ParseEvent {
    let itemStart = buffer.mark()
    let initByte = try readByte()

    switch initByte {
    // positive integers (0x00..0x1B)
    case 0x00...0x1B:
      _ = try readVarUInt(initByte, base: 0x00)
      let region = buffer.region(from: itemStart, to: buffer.mark())
      return try emitScalar(ScalarRef(kind: .integer, region: region))

    // negative integers (0x20..0x3B)
    case 0x20...0x3B:
      _ = try readVarUInt(initByte, base: 0x20)
      let region = buffer.region(from: itemStart, to: buffer.mark())
      return try emitScalar(ScalarRef(kind: .integer, region: region))

    // byte strings (0x40..0x5B)
    case 0x40...0x5B:
      let numBytes = try readLength(initByte, base: 0x40)
      let region = try readRegion(count: numBytes)
      return try emitScalar(ScalarRef(kind: .bytes, region: region))

    // indefinite byte string (0x5F)
    case 0x5F:
      let bytes = try readIndefiniteByteString()
      return try emitScalar(.materialized(.bytes(bytes)))

    // UTF-8 strings (0x60..0x7B)
    case 0x60...0x7B:
      let numBytes = try readLength(initByte, base: 0x60)
      let region = try readRegion(count: numBytes)
      return try emitScalar(ScalarRef(kind: .string, region: region))

    // indefinite string (0x7F)
    case 0x7F:
      let string = try readIndefiniteString()
      return try emitScalar(.materialized(.string(string)))

    // arrays (0x80..0x9B)
    case 0x80...0x9B:
      let itemCount = try readLength(initByte, base: 0x80)
      try validateContainerPosition()
      containers.pushArray(count: itemCount)
      return .beginArray(count: itemCount)

    // indefinite array (0x9F)
    case 0x9F:
      try validateContainerPosition()
      containers.pushArray(count: nil)
      return .beginArray(count: nil)

    // maps (0xA0..0xBB)
    case 0xA0...0xBB:
      let itemPairCount = try readLength(initByte, base: 0xA0)
      try validateContainerPosition()
      containers.pushObject(count: itemPairCount)
      return .beginObject(count: itemPairCount)

    // indefinite map (0xBF)
    case 0xBF:
      try validateContainerPosition()
      containers.pushObject(count: nil)
      return .beginObject(count: nil)

    // tags (0xC0..0xDB)
    case 0xC0...0xDB:
      let tag = try readVarUInt(initByte, base: 0xC0)
      switch tag {
      case CBORStructure.Tags.positiveBignum:
        let value = try decodeBigInt(isNegative: false)
        return try emitScalar(.materialized(value))
      case CBORStructure.Tags.negativeBignum:
        let value = try decodeBigInt(isNegative: true)
        return try emitScalar(.materialized(value))
      case CBORStructure.Tags.decimalFractionTag:
        let value = try decodeBigNumber(base: Self.decimalFractionRadix)
        return try emitScalar(.materialized(value))
      case CBORStructure.Tags.bigFloatTag:
        let value = try decodeBigNumber(base: Self.bigFloatRadix)
        return try emitScalar(.materialized(value))
      default:
        return .tag(.materialized(.number(tag)))
      }

    // simple values (0xE0..0xF3)
    case 0xE0...0xF3:
      return try emitScalar(.materialized(.number(initByte - 0xE0)))

    case 0xF4:
      return try emitScalar(.bool(false))

    case 0xF5:
      return try emitScalar(.bool(true))

    case 0xF6:
      return try emitScalar(.null)

    case 0xF7:
      switch options.undefined {
      case .throwError:
        throw CBOR.Error.undefinedItem
      case .convertToNull:
        return try emitScalar(.null)
      }

    case 0xF8:
      let value = try readByte()
      return try emitScalar(.materialized(.number(value)))

    case 0xF9:
      try advance(count: 2)
      let region = buffer.region(from: itemStart, to: buffer.mark())
      return try emitScalar(ScalarRef(kind: .float, region: region))

    case 0xFA:
      try advance(count: 4)
      let region = buffer.region(from: itemStart, to: buffer.mark())
      return try emitScalar(ScalarRef(kind: .float, region: region))

    case 0xFB:
      try advance(count: 8)
      let region = buffer.region(from: itemStart, to: buffer.mark())
      return try emitScalar(ScalarRef(kind: .float, region: region))

    case 0xFF:
      throw CBOR.Error.invalidBreak

    default:
      throw CBOR.Error.invalidItemType
    }
  }

  // MARK: - Event emission helpers

  /// Emit a scalar event and update container tracking.
  private mutating func emitScalar(_ ref: ScalarRef) throws -> ParseEvent {
    try didFinishScalarValue()
    return .scalar(ref)
  }

  /// Validate that a container (array/map) is allowed at the current position.
  private mutating func validateContainerPosition() throws {
    // Containers don't finish a value — they start one.
    // The value is finished when endArray/endObject is emitted.
    // No validation needed here beyond what the container tracking already does.
  }

  /// Update container tracking after a scalar value or container end.
  private mutating func didFinishScalarValue() throws {
    guard !containers.isEmpty else {
      completedRootValue = true
      return
    }
    containers.didFinishScalarValue()
  }

  /// Update container tracking after a container end (endArray/endObject).
  private mutating func didFinishContainerValue() throws {
    guard !containers.isEmpty else {
      completedRootValue = true
      return
    }
    containers.didFinishContainerValue()
  }

  // MARK: - Container completion

  /// Check if a definite-length container has all items and emit the end event.
  private mutating func emitCompletedContainerIfNeeded() throws -> ParseEvent? {
    guard let frame = containers.completedDefiniteContainer else { return nil }

    switch frame {
    case .array:
      _ = try containers.pop()
      try didFinishContainerValue()
      return .endArray

    case .object:
      _ = try containers.pop()
      try didFinishContainerValue()
      return .endObject
    }
  }

  /// Check for a break byte (0xFF) ending an indefinite-length container.
  private mutating func emitBreakIfNeeded() throws -> ParseEvent? {
    guard containers.canConsumeBreak else { return nil }
    guard let byte = buffer.peekByte(), byte == 0xFF else { return nil }

    _ = try readByte() // consume break byte
    let removedFrame = try containers.pop()
    try didFinishContainerValue()

    switch removedFrame {
    case .array:
      return .endArray
    case .object:
      return .endObject
    }
  }

  // MARK: - Tag helpers

  private static let decimalFractionRadix: BigDecimal = .ten
  private static let bigFloatRadix: BigDecimal = 2

  /// Decode a bignum tag (tag 2 or 3) — reads the next item which must be a byte string.
  private mutating func decodeBigInt(isNegative: Bool) throws -> Value {
    let initByte = try readByte()
    let bytes: Data
    switch initByte {
    case 0x40...0x5B:
      let numBytes = try readLength(initByte, base: 0x40)
      bytes = try readBytes(count: numBytes)
    case 0x5F:
      bytes = try readIndefiniteByteString()
    default:
      throw CBOR.Error.invalidItemType
    }
    guard !bytes.isEmpty else {
      throw CBOR.Error.invalidItemType
    }
    return .number(BigInt(isNegative: isNegative, magnitude: BigUInt(encoded: bytes)))
  }

  /// Decode a decimal fraction (tag 4) or big float (tag 5).
  /// The tagged item must be a 2-element array [exponent, mantissa].
  private mutating func decodeBigNumber(base: BigDecimal) throws -> Value {
    let initByte = try readByte()
    guard (0x82...0x82).contains(initByte) else {
      // Must be a definite-length array of exactly 2 items
      if (0x80...0x9B).contains(initByte) {
        let count = try readLength(initByte, base: 0x80)
        guard count == 2 else { throw CBOR.Error.invalidItemType }
      } else {
        throw CBOR.Error.invalidItemType
      }
      // Fall through to read the two items
      let exponent = try readScalarValue()
      let mantissa = try readScalarValue()
      return try assembleBigNumber(exponent: exponent, mantissa: mantissa, base: base)
    }

    // Fast path: exactly 2-element array (0x82)
    let exponent = try readScalarValue()
    let mantissa = try readScalarValue()
    return try assembleBigNumber(exponent: exponent, mantissa: mantissa, base: base)
  }

  private func assembleBigNumber(exponent: Value, mantissa: Value, base: BigDecimal) throws -> Value {
    guard
      case .number(let exponentNum) = exponent,
      case .number(let mantissaNum) = mantissa
    else {
      throw CBOR.Error.invalidItemType
    }
    guard let exp = Int(exactly: exponentNum.decimal) else {
      throw CBOR.Error.unsupportedValue
    }
    let decimal = mantissaNum.decimal * base.raised(to: exp)
    return .number(decimal)
  }

  /// Read a single scalar CBOR value (for tag content parsing).
  /// Only handles scalar types — not containers.
  private mutating func readScalarValue() throws -> Value {
    let initByte = try readByte()

    switch initByte {
    case 0x00...0x1B:
      return .number(try readVarUInt(initByte, base: 0x00))
    case 0x20...0x3B:
      let magnitude = try readVarUInt(initByte, base: 0x20)
      if magnitude <= UInt64(Int64.max) {
        return .number(-1 - Int64(magnitude))
      }
      return .number(-(BigInt(magnitude) + 1))
    case 0xC0...0xDB:
      let tag = try readVarUInt(initByte, base: 0xC0)
      switch tag {
      case CBORStructure.Tags.positiveBignum:
        return try decodeBigInt(isNegative: false)
      case CBORStructure.Tags.negativeBignum:
        return try decodeBigInt(isNegative: true)
      default:
        throw CBOR.Error.invalidItemType
      }
    case 0xE0...0xF3:
      return .number(initByte - 0xE0)
    case 0xF9:
      return .number(try readHalf())
    case 0xFA:
      return .number(try readFloat())
    case 0xFB:
      return .number(try readDouble())
    default:
      throw CBOR.Error.invalidItemType
    }
  }

  // MARK: - String and byte string helpers

  private mutating func readFiniteStringBytes(initByte: UInt8) throws -> Data {
    let numBytes = try readLength(initByte, base: 0x60)
    return try readBytes(count: numBytes)
  }

  private mutating func readIndefiniteString() throws -> String {
    var result = Data()
    while true {
      let initByte = try readByte()
      if initByte == 0xFF { break }
      guard (0x60...0x7B).contains(initByte) else { throw CBOR.Error.invalidIndefiniteElement }
      result.append(try readFiniteStringBytes(initByte: initByte))
    }
    guard let string = String(data: result, encoding: .utf8) else {
      throw CBOR.Error.invalidUTF8String
    }
    return string
  }

  private mutating func readIndefiniteByteString() throws -> Data {
    var result = Data()
    while true {
      let initByte = try readByte()
      if initByte == 0xFF { break }
      guard (0x40...0x5B).contains(initByte) else { throw CBOR.Error.invalidIndefiniteElement }
      let numBytes = try readLength(initByte, base: 0x40)
      result.append(try readBytes(count: numBytes))
    }
    return result
  }

  // MARK: - Byte reading

  private mutating func readByte() throws -> UInt8 {
    do {
      return try buffer.readByte()
    } catch ParseBufferError.unexpectedEnd {
      throw CBOR.Error.unexpectedEndOfStream
    }
  }

  private mutating func readBytes(count: Int) throws -> Data {
    guard count >= 0 else { return Data() }
    do {
      return try buffer.readBytes(count: count)
    } catch ParseBufferError.unexpectedEnd {
      throw CBOR.Error.unexpectedEndOfStream
    }
  }

  private mutating func advance(count: Int) throws {
    do {
      try buffer.advance(count: count)
    } catch ParseBufferError.unexpectedEnd {
      throw CBOR.Error.unexpectedEndOfStream
    }
  }

  private mutating func readRegion(count: Int) throws -> ParseBuffer.Region {
    do {
      return try buffer.readRegion(count: count)
    } catch ParseBufferError.unexpectedEnd {
      throw CBOR.Error.unexpectedEndOfStream
    }
  }

  private mutating func readInt<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
    do {
      return try buffer.readInt(T.self)
    } catch ParseBufferError.unexpectedEnd {
      throw CBOR.Error.unexpectedEndOfStream
    }
  }

  private mutating func readHalf() throws -> Float16 {
    Float16(bitPattern: try readInt(UInt16.self))
  }

  private mutating func readFloat() throws -> Float32 {
    Float32(bitPattern: try readInt(UInt32.self))
  }

  private mutating func readDouble() throws -> Float64 {
    Float64(bitPattern: try readInt(UInt64.self))
  }

  private mutating func readVarUInt(_ initByte: UInt8, base: UInt8) throws -> UInt64 {
    guard initByte > base + 0x17 else { return UInt64(initByte - base) }

    switch try VarUIntSize.from(serialized: initByte) {
    case .uint8:
      return UInt64(try readInt(UInt8.self))
    case .uint16:
      return UInt64(try readInt(UInt16.self))
    case .uint32:
      return UInt64(try readInt(UInt32.self))
    case .uint64:
      return UInt64(try readInt(UInt64.self))
    }
  }

  private mutating func readLength(_ initByte: UInt8, base: UInt8) throws -> Int {
    let length = try readVarUInt(initByte, base: base)
    guard length <= Int.max else {
      throw CBOR.Error.sequenceTooLong
    }
    return Int(length)
  }
}

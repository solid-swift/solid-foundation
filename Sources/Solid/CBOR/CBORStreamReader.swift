//
//  CBORStreamReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/17/26.
//

import Collections
import Foundation
import SolidData
import SolidNumeric

/// Synchronous CBOR stream reader that produces ``ValueEvent`` values.
public struct CBORStreamReader: FormatStreamReader {

  private enum Frame {
    case array(remaining: Int?)
    case map(remaining: Int?, expectingKey: Bool)

    var isIndefinite: Bool {
      switch self {
      case .array(let remaining):
        return remaining == nil
      case .map(let remaining, _):
        return remaining == nil
      }
    }
  }

  private enum ParseResult {
    case scalar(Value)
    case beginArray(count: Int?)
    case beginMap(count: Int?)
    case tag(UInt64)
  }

  private var inputBuffer = CBORInputBuffer()
  private var frames: [Frame] = []
  private var pendingEvents: Deque<ValueEvent> = []
  private var finished = false
  private var completedRootInCall = false
  private let options: CBORValueReader.Options

  public init(options: CBORValueReader.Options = CBORValueReader.Options()) {
    self.options = options
  }

  public var format: Format { CBOR.format }

  public mutating func read(
    input: Data,
    isFinal: Bool,
    output: inout OutputSpan<ValueEvent>
  ) throws -> FormatStreamReadStatus {
    guard !finished else { return .endOfStream }
    completedRootInCall = false

    if !input.isEmpty {
      inputBuffer.append(input)
    }

    var produced = false

    defer {
      inputBuffer.compactSegments()
    }

    while !output.isFull {
      if let event = try nextEvent(isFinal: isFinal) {
        output.append(event)
        produced = true
        if completedRootInCall {
          return .producedOutput
        }
        continue
      }

      if finished {
        return produced ? .producedOutput : .endOfStream
      }
      return produced ? .producedOutput : .needMoreInput
    }

    return .producedOutput
  }

  private mutating func nextEvent(isFinal: Bool) throws -> ValueEvent? {
    if completedRootInCall {
      return nil
    }

    if !pendingEvents.isEmpty {
      return pendingEvents.removeFirst()
    }

    if let completion = try emitCompletedContainerIfNeeded() {
      return completion
    }

    if inputBuffer.peekByte() == nil {
      if isFinal {
        if !frames.isEmpty {
          throw CBOR.Error.unexpectedEndOfStream
        }
        finished = true
      }
      return nil
    }

    if let breakEvent = try emitBreakIfNeeded() {
      return breakEvent
    }

    if case .map(_, let expectingKey) = frames.last, expectingKey {
      let mark = inputBuffer.mark()
      do {
        let key = try decodeRequiredItem()
        try didFinishKey()
        return .key(key)
      } catch CBOR.Error.unexpectedEndOfStream {
        inputBuffer.restore(mark)
        if isFinal {
          throw CBOR.Error.unexpectedEndOfStream
        }
        return nil
      }
    }

    let mark = inputBuffer.mark()
    do {
      let result = try parseValue()
      switch result {
      case .scalar(let value):
        try didFinishValue()
        if frames.isEmpty {
          completedRootInCall = true
        }
        return .scalar(value)
      case .beginArray(let count):
        frames.append(.array(remaining: count))
        return .beginArray(count: count)
      case .beginMap(let count):
        frames.append(.map(remaining: count, expectingKey: true))
        return .beginObject(count: count)
      case .tag(let tag):
        return .tag(.number(tag))
      }
    } catch CBOR.Error.unexpectedEndOfStream {
      inputBuffer.restore(mark)
      if isFinal {
        throw CBOR.Error.unexpectedEndOfStream
      }
      return nil
    }
  }

  private mutating func emitCompletedContainerIfNeeded() throws -> ValueEvent? {
    guard let frame = frames.last else { return nil }

    switch frame {
    case .array(let remaining):
      if remaining == 0 {
        _ = frames.popLast()
        try didFinishValue()
        if frames.isEmpty {
          completedRootInCall = true
        }
        return .endArray
      }
    case .map(let remaining, let expectingKey):
      if let remaining, remaining == 0 {
        if !expectingKey {
          throw CBOR.Error.unexpectedEndOfStream
        }
        _ = frames.popLast()
        try didFinishValue()
        if frames.isEmpty {
          completedRootInCall = true
        }
        return .endObject
      }
    }
    return nil
  }

  private mutating func emitBreakIfNeeded() throws -> ValueEvent? {
    guard let frame = frames.last, frame.isIndefinite else { return nil }
    guard inputBuffer.peekByte() != nil else { return nil }

    if case .map(_, let expectingKey) = frame, !expectingKey {
      return nil
    }

    if inputBuffer.peekByte() == 0xFF {
      _ = try inputBuffer.readByte()
      _ = frames.popLast()
      try didFinishValue()
      if frames.isEmpty {
        completedRootInCall = true
      }
      switch frame {
      case .array:
        return .endArray
      case .map:
        return .endObject
      }
    }

    return nil
  }

  private mutating func didFinishKey() throws {
    guard case .map(let remaining, let expectingKey) = frames.popLast() else {
      throw CBOR.Error.invalidBreak
    }
    guard expectingKey else {
      throw CBOR.Error.invalidBreak
    }
    frames.append(.map(remaining: remaining, expectingKey: false))
  }

  private mutating func didFinishValue() throws {
    guard var frame = frames.popLast() else {
      return
    }

    switch frame {
    case .array(let remaining):
      if let remaining {
        let updated = remaining - 1
        frame = .array(remaining: updated)
      }
      frames.append(frame)

    case .map(let remaining, let expectingKey):
      if expectingKey {
        throw CBOR.Error.invalidBreak
      }
      if let remaining {
        let updated = remaining - 1
        frame = .map(remaining: updated, expectingKey: true)
      } else {
        frame = .map(remaining: nil, expectingKey: true)
      }
      frames.append(frame)
    }
  }

  // MARK: - Parsing

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

  private mutating func parseValue() throws -> ParseResult {
    let initByte = try readByte()

    switch initByte {
    // positive integers
    case 0x00...0x1B:
      return .scalar(.number(try readVarUInt(initByte, base: 0x00)))

    // negative integers
    case 0x20...0x3B:
      let magnitude = try readVarUInt(initByte, base: 0x20)
      if magnitude <= UInt64(Int64.max) {
        return .scalar(.number(-1 - Int64(magnitude)))
      }
      let bigValue = BigInt(magnitude)
      return .scalar(.number(-(bigValue + 1)))

    // byte strings
    case 0x40...0x5B:
      let numBytes = try readLength(initByte, base: 0x40)
      return .scalar(.bytes(try readBytes(count: numBytes)))
    case 0x5F:
      return .scalar(.bytes(try readIndefiniteByteString()))

    // utf-8 strings
    case 0x60...0x7B:
      return .scalar(.string(try readFiniteString(initByte: initByte)))
    case 0x7F:
      return .scalar(.string(try readIndefiniteString()))

    // arrays
    case 0x80...0x9B:
      let itemCount = try readLength(initByte, base: 0x80)
      return .beginArray(count: itemCount)
    case 0x9F:
      return .beginArray(count: nil)

    // maps
    case 0xA0...0xBB:
      let itemPairCount = try readLength(initByte, base: 0xA0)
      return .beginMap(count: itemPairCount)
    case 0xBF:
      return .beginMap(count: nil)

    // tags
    case 0xC0...0xDB:
      let tag = try readVarUInt(initByte, base: 0xC0)
      switch tag {
      case CBORStructure.Tags.positiveBignum:
        return .scalar(try decodeBigInt(isNegative: false))
      case CBORStructure.Tags.negativeBignum:
        return .scalar(try decodeBigInt(isNegative: true))
      case CBORStructure.Tags.decimalFractionTag:
        return .scalar(try decodeBigNumber(base: Self.decimalFractionRadix))
      case CBORStructure.Tags.bigFloatTag:
        return .scalar(try decodeBigNumber(base: Self.bigFloatRadix))
      default:
        return .tag(tag)
      }

    case 0xE0...0xF3:
      return .scalar(.number(initByte - 0xE0))

    case 0xF4:
      return .scalar(.bool(false))

    case 0xF5:
      return .scalar(.bool(true))

    case 0xF6:
      return .scalar(.null)

    case 0xF7:
      switch options.undefined {
      case .throwError:
        throw CBOR.Error.undefinedItem
      case .convertToNull:
        return .scalar(.null)
      }

    case 0xF8:
      return .scalar(.number(try readByte()))

    case 0xF9:
      return .scalar(.number(try readHalf()))
    case 0xFA:
      return .scalar(.number(try readFloat()))
    case 0xFB:
      return .scalar(.number(try readDouble()))

    case 0xFF:
      throw CBOR.Error.invalidBreak

    default:
      throw CBOR.Error.invalidItemType
    }
  }

  // MARK: - Value decoding (for map keys and tag helpers)

  private mutating func decodeRequiredItem() throws -> Value {
    guard let item = try decodeItem() else { throw CBOR.Error.invalidBreak }
    return item
  }

  private mutating func decodeItem() throws -> Value? {
    let initByte = try readByte()

    switch initByte {
    case 0x00...0x1B:
      return .number(try readVarUInt(initByte, base: 0x00))

    case 0x20...0x3B:
      let magnitude = try readVarUInt(initByte, base: 0x20)
      if magnitude <= UInt64(Int64.max) {
        return .number(-1 - Int64(magnitude))
      }
      let bigValue = BigInt(magnitude)
      return .number(-(bigValue + 1))

    case 0x40...0x5B:
      let numBytes = try readLength(initByte, base: 0x40)
      return .bytes(try readBytes(count: numBytes))
    case 0x5F:
      return .bytes(try readIndefiniteByteString())

    case 0x60...0x7B:
      return .string(try readFiniteString(initByte: initByte))
    case 0x7F:
      return .string(try readIndefiniteString())

    case 0x80...0x9B:
      let itemCount = try readLength(initByte, base: 0x80)
      return .array(try decodeItems(count: itemCount))
    case 0x9F:
      return .array(try decodeItemsUntilBreak())

    case 0xA0...0xBB:
      let itemPairCount = try readLength(initByte, base: 0xA0)
      return .object(try decodeItemPairs(count: itemPairCount))
    case 0xBF:
      return .object(try decodeItemPairsUntilBreak())

    case 0xC0...0xDB:
      let tag = try readVarUInt(initByte, base: 0xC0)
      switch tag {
      case CBORStructure.Tags.positiveBignum:
        return try decodeBigInt(isNegative: false)
      case CBORStructure.Tags.negativeBignum:
        return try decodeBigInt(isNegative: true)
      case CBORStructure.Tags.decimalFractionTag:
        return try decodeBigNumber(base: Self.decimalFractionRadix)
      case CBORStructure.Tags.bigFloatTag:
        return try decodeBigNumber(base: Self.bigFloatRadix)
      default:
        let item = try decodeRequiredItem()
        return .tagged(tag: .number(tag), value: item)
      }

    case 0xE0...0xF3:
      return .number(initByte - 0xE0)

    case 0xF4:
      return .bool(false)

    case 0xF5:
      return .bool(true)

    case 0xF6:
      return .null

    case 0xF7:
      switch options.undefined {
      case .throwError:
        throw CBOR.Error.undefinedItem
      case .convertToNull:
        return .null
      }

    case 0xF8:
      return .number(try readByte())

    case 0xF9:
      return .number(try readHalf())
    case 0xFA:
      return .number(try readFloat())
    case 0xFB:
      return .number(try readDouble())

    case 0xFF:
      return nil

    default:
      throw CBOR.Error.invalidItemType
    }
  }

  private mutating func decodeItems(count: Int) throws -> Value.Array {
    var result: Value.Array = []
    for _ in 0..<count {
      let item = try decodeRequiredItem()
      result.append(item)
    }
    return result
  }

  private mutating func decodeItemsUntilBreak() throws -> Value.Array {
    var result: Value.Array = []
    while let item = try decodeItem() {
      result.append(item)
    }
    return result
  }

  private mutating func decodeItemPairs(count: Int) throws -> Value.Object {
    var result: Value.Object = [:]
    for _ in 0..<count {
      let key = try decodeRequiredItem()
      let val = try decodeRequiredItem()
      result[key] = val
    }
    return result
  }

  private mutating func decodeItemPairsUntilBreak() throws -> Value.Object {
    var result: Value.Object = [:]
    while let key = try decodeItem() {
      let val = try decodeRequiredItem()
      result[key] = val
    }
    return result
  }

  private static let decimalFractionRadix: BigDecimal = .ten
  private static let bigFloatRadix: BigDecimal = 2

  private mutating func decodeBigInt(isNegative: Bool) throws -> Value {
    let item = try decodeRequiredItem()
    guard case .bytes(let bytes) = item, !bytes.isEmpty else {
      throw CBOR.Error.invalidItemType
    }
    return .number(BigInt(isNegative: isNegative, magnitude: BigUInt(encoded: bytes)))
  }

  private mutating func decodeBigNumber(base: BigDecimal) throws -> Value {
    let item = try decodeRequiredItem()
    guard
      case .array(let items) = item, items.count == 2,
      case .number(let exponentNum) = items[0],
      case .number(let mantissaNum) = items[1]
    else {
      throw CBOR.Error.invalidItemType
    }
    guard let exponent = Int(exactly: exponentNum.decimal) else {
      throw CBOR.Error.unsupportedValue
    }
    let decimal = mantissaNum.decimal * base.raised(to: exponent)
    return .number(decimal)
  }

  private mutating func readFiniteString(initByte: UInt8) throws -> String {
    let numBytes = try readLength(initByte, base: 0x60)
    guard let string = String(data: try readBytes(count: numBytes), encoding: .utf8) else {
      throw CBOR.Error.invalidUTF8String
    }
    return string
  }

  private mutating func readIndefiniteString() throws -> String {
    return try decodeItemsUntilBreak()
      .map { item -> String in
        guard case .string(let string) = item else { throw CBOR.Error.invalidIndefiniteElement }
        return string
      }
      .joined(separator: "")
  }

  private mutating func readIndefiniteByteString() throws -> Data {
    let datas = try decodeItemsUntilBreak()
      .map { item -> Data in
        guard case .bytes(let bytes) = item else { throw CBOR.Error.invalidIndefiniteElement }
        return bytes
      }
      .joined()
    return Data(datas)
  }

  // MARK: - Byte Reading

  private mutating func readByte() throws -> UInt8 {
    return try inputBuffer.readByte()
  }

  private mutating func readBytes(count: Int) throws -> Data {
    return try inputBuffer.readBytes(count: count)
  }

  private mutating func readInt<T>(_ type: T.Type) throws -> T where T: FixedWidthInteger {
    return try inputBuffer.readInt(type)
  }

  private mutating func readHalf() throws -> Float16 {
    return Float16(bitPattern: try readInt(UInt16.self))
  }

  private mutating func readFloat() throws -> Float32 {
    return Float32(bitPattern: try readInt(UInt32.self))
  }

  private mutating func readDouble() throws -> Float64 {
    return Float64(bitPattern: try readInt(UInt64.self))
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

private struct CBORInputBuffer {

  struct Position: Sendable {
    let index: Int
    let offset: Int
  }

  private var inline: InlineArray<2, Data?> = InlineArray(repeating: nil)
  private var overflow: [Data] = []
  private var count: Int = 0
  private var index: Int = 0
  private var offset: Int = 0

  var isEmpty: Bool {
    var idx = index
    var off = offset
    while idx < count {
      guard let segment = segment(at: idx) else {
        idx += 1
        off = 0
        continue
      }
      if off < segment.count {
        return false
      }
      idx += 1
      off = 0
    }
    return true
  }

  mutating func append(_ data: Data) {
    guard !data.isEmpty else { return }
    if count < 2 {
      inline[count] = data
    } else {
      overflow.append(data)
    }
    count += 1
  }

  func mark() -> Position {
    Position(index: index, offset: offset)
  }

  mutating func restore(_ position: Position) {
    index = position.index
    offset = position.offset
  }

  mutating func compactSegments() {
    _ = ensureCurrentSegment()
    guard index > 0 else { return }

    var newInline: InlineArray<2, Data?> = InlineArray(repeating: nil)
    var newOverflow: [Data] = []
    var newCount = 0

    for idx in index..<count {
      guard let segment = segment(at: idx) else { continue }
      if newCount < 2 {
        newInline[newCount] = segment
      } else {
        newOverflow.append(segment)
      }
      newCount += 1
    }

    inline = newInline
    overflow = newOverflow
    count = newCount
    index = 0
  }

  mutating func peekByte() -> UInt8? {
    guard let segment = ensureCurrentSegment() else { return nil }
    return segment[offset]
  }

  mutating func readByte() throws -> UInt8 {
    guard let segment = ensureCurrentSegment() else { throw CBOR.Error.unexpectedEndOfStream }
    let byte = segment[offset]
    offset += 1
    return byte
  }

  mutating func readBytes(count: Int) throws -> Data {
    guard count >= 0 else { return Data() }
    guard hasAvailable(count) else { throw CBOR.Error.unexpectedEndOfStream }
    guard count > 0 else { return Data() }

    guard let segment = ensureCurrentSegment() else { throw CBOR.Error.unexpectedEndOfStream }
    if offset + count <= segment.count {
      let range = offset..<(offset + count)
      offset += count
      return Self.makeNoCopySlice(from: segment, range: range)
    }

    var remaining = count
    var result = Data()
    result.reserveCapacity(count)

    while remaining > 0 {
      guard let current = ensureCurrentSegment() else { throw CBOR.Error.unexpectedEndOfStream }
      let available = current.count - offset
      let take = min(available, remaining)
      let range = offset..<(offset + take)
      result.append(current.subdata(in: range))
      offset += take
      remaining -= take
    }

    return result
  }

  mutating func readInt<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
    let size = MemoryLayout<T>.size
    guard hasAvailable(size) else { throw CBOR.Error.unexpectedEndOfStream }
    guard let segment = ensureCurrentSegment() else { throw CBOR.Error.unexpectedEndOfStream }

    if offset + size <= segment.count {
      let value: T = segment.withUnsafeBytes { rawBuffer in
        rawBuffer.loadUnaligned(fromByteOffset: offset, as: T.self)
      }
      offset += size
      return T(bigEndian: value)
    }

    let bytes = try readBytes(count: size)
    let value: T = bytes.withUnsafeBytes { rawBuffer in
      rawBuffer.loadUnaligned(as: T.self)
    }
    return T(bigEndian: value)
  }

  private func hasAvailable(_ count: Int) -> Bool {
    var remaining = count
    var idx = index
    var off = offset

    while remaining > 0 {
      guard let segment = segment(at: idx) else { return false }
      let available = segment.count - off
      if available >= remaining {
        return true
      }
      remaining -= available
      idx += 1
      off = 0
    }

    return true
  }

  private func segment(at idx: Int) -> Data? {
    guard idx < count else { return nil }
    if idx < 2 {
      return inline[idx]
    }
    let overflowIndex = idx - 2
    guard overflowIndex < overflow.count else { return nil }
    return overflow[overflowIndex]
  }

  private mutating func ensureCurrentSegment() -> Data? {
    while index < count {
      guard let segment = segment(at: index) else {
        index += 1
        offset = 0
        continue
      }
      if offset < segment.count {
        return segment
      }
      index += 1
      offset = 0
    }
    return nil
  }

  private static func makeNoCopySlice(from segment: Data, range: Range<Int>) -> Data {
    guard !range.isEmpty else { return Data() }
    return segment.withUnsafeBytes { rawBuffer in
      guard let base = rawBuffer.baseAddress else { return Data() }
      let pointer = base.advanced(by: range.lowerBound)
      return Data(
        bytesNoCopy: UnsafeMutableRawPointer(mutating: pointer),
        count: range.count,
        deallocator: .custom { _, _ in
          _ = segment
        }
      )
    }
  }
}

//
//  CBOREncoder.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/18/26.
//

import Foundation
import SolidData
import SolidNumeric

enum CBORStreamItemType: UInt8 {
  case map = 0xBF
  case array = 0x9F
  case string = 0x7F
  case byteString = 0x5F
}

/// Typealias for the stream encoder wrapping ``CBOREncoder`` with buffer management.
typealias CBORStreamEncoder = BufferedStreamEncoder<CBOREncoder>

struct CBOREncoder: FormatEventWriter {

  enum Error: Swift.Error {
    case invalidEventSequence(String)
    case incompleteCBOR
    case alreadyFinished
    case invalidTagValue
  }

  enum DeterministicMode: Sendable, Equatable {
    case none
    case sortMapEvents
  }

  struct Options: Sendable {
    var deterministic: Bool
    var deterministicMode: DeterministicMode

    init(
      deterministic: Bool = false,
      deterministicMode: DeterministicMode = .none
    ) {
      self.deterministic = deterministic
      self.deterministicMode = deterministicMode
    }
  }

  private enum RootState {
    case expectingValue
    case complete
  }

  private let options: Options

  var buffer = Data()
  private var rootState: RootState = .expectingValue
  private var containers = ContainerStack()
  private var pendingTags: [UInt64] = []
  private var mapBuffer: MapBuffer?

  var format: Format { CBOR.format }

  init(options: Options = Options()) {
    self.options = options
  }

  static func encodeValue(_ value: Value, deterministic: Bool) throws -> Data {
    var encoder = CBOREncoder(options: Options(deterministic: deterministic, deterministicMode: .none))
    try encoder.writeValue(value)
    return encoder.buffer
  }

  static func encodeEmitEvents(_ events: [EmitEvent], options: Options) throws -> Data {
    let streamEncoder = CBORStreamEncoder(writer: CBOREncoder(options: options))
    var encoderBuffer = FormatStreamEncoderBuffer(encoder: streamEncoder)
    return try encoderBuffer.encode(events: events)
  }

  // MARK: - FormatEventWriter

  mutating func writeEvent(_ event: EmitEvent, into output: inout Data) throws {
    swap(&buffer, &output)
    defer { swap(&buffer, &output) }
    try writeEventImpl(event)
  }

  mutating func finishWriting(into output: inout Data) throws {
    guard mapBuffer == nil else {
      throw Error.incompleteCBOR
    }
    guard containers.isEmpty, pendingTags.isEmpty, rootState == .complete else {
      throw Error.incompleteCBOR
    }
  }

  // MARK: - Event Encoding

  private mutating func writeEventImpl(_ event: EmitEvent) throws {
    if var mapBuf = takeMapBuffer() {
      if let completion = try mapBuf.handle(event) {
        try emitBufferedMap(completion)
      } else {
        mapBuffer = mapBuf
      }
      return
    }

    if case .beginObject(let count) = event, options.deterministicMode == .sortMapEvents {
      guard let count else {
        throw Error.invalidEventSequence("Indefinite map not allowed in deterministic mode")
      }
      try prepareForValue(isKey: false)
      mapBuffer = MapBuffer(expectedPairs: count)
      return
    }

    if options.deterministic {
      switch event {
      case .beginArray(count: nil):
        throw Error.invalidEventSequence("Indefinite array not allowed in deterministic mode")
      case .beginObject(count: nil):
        throw Error.invalidEventSequence("Indefinite map not allowed in deterministic mode")
      default:
        break
      }
    }

    switch event {
    case .style:
      break

    case .tag(let tag):
      pendingTags.append(try tagValue(tag))

    case .anchor:
      throw Error.invalidEventSequence("Anchors are not supported")

    case .alias:
      throw Error.invalidEventSequence("Aliases are not supported")

    case .scalar(let value):
      if containers.isExpectingObjectKey {
        try prepareForValue(isKey: true)
        writePendingTags()
        try writeValue(value)
        try setObjectExpectingValue()
      } else {
        try prepareForValue(isKey: false)
        writePendingTags()
        try writeValue(value)
        try finishValue()
      }

    case .beginArray(let count):
      try prepareForValue(isKey: false)
      writePendingTags()
      if let count {
        writeLength(count, majorType: 0b100)
        containers.pushArray(count: count)
      } else {
        writeIndefiniteStart(for: .array)
        containers.pushArray(count: nil)
      }

    case .endArray:
      guard pendingTags.isEmpty else {
        throw Error.invalidEventSequence("Tag without value")
      }
      guard case .array(let remaining) = try containers.pop() else {
        throw Error.invalidEventSequence("Unexpected endArray")
      }
      if let remaining, remaining != 0 {
        throw Error.invalidEventSequence("Missing array values")
      }
      if remaining == nil {
        writeIndefiniteEnd()
      }
      try finishValue()

    case .beginObject(let count):
      try prepareForValue(isKey: false)
      writePendingTags()
      if let count {
        writeLength(count, majorType: 0b101)
        containers.pushObject(count: count)
      } else {
        writeIndefiniteStart(for: .map)
        containers.pushObject(count: nil)
      }

    case .endObject:
      guard pendingTags.isEmpty else {
        throw Error.invalidEventSequence("Tag without value")
      }
      guard case .object(let remaining, let expectingKey) = try containers.pop() else {
        throw Error.invalidEventSequence("Unexpected endObject")
      }
      guard expectingKey else {
        throw Error.invalidEventSequence("Missing value for key")
      }
      if let remaining, remaining != 0 {
        throw Error.invalidEventSequence("Missing object values")
      }
      if remaining == nil {
        writeIndefiniteEnd()
      }
      try finishValue()
    }
  }

  private mutating func takeMapBuffer() -> MapBuffer? {
    let buffer = mapBuffer
    mapBuffer = nil
    return buffer
  }

  private mutating func prepareForValue(isKey: Bool) throws {
    if containers.isEmpty {
      guard rootState == .expectingValue else {
        throw Error.invalidEventSequence("Unexpected value after root")
      }
      return
    }
    guard let current = containers.current else {
      return
    }
    switch current {
    case .array(let remaining):
      if let remaining, remaining == 0 {
        throw Error.invalidEventSequence("Too many array values")
      }
      return
    case .object(let remaining, let expectingKey):
      if isKey {
        if let remaining, remaining == 0 {
          throw Error.invalidEventSequence("Too many object values")
        }
        guard expectingKey else {
          throw Error.invalidEventSequence("Unexpected key")
        }
      } else {
        if let remaining, remaining == 0 {
          throw Error.invalidEventSequence("Too many object values")
        }
        guard !expectingKey else {
          throw Error.invalidEventSequence("Value without key")
        }
      }
    }
  }

  private mutating func setObjectExpectingValue() throws {
    guard case .object(_, let expectingKey) = containers.current else {
      throw Error.invalidEventSequence("Key outside map")
    }
    guard expectingKey else {
      throw Error.invalidEventSequence("Unexpected key")
    }
    containers.didFinishScalarValue()
  }

  private mutating func finishValue() throws {
    if containers.isEmpty {
      rootState = .complete
      return
    }
    if case .object(_, let expectingKey) = containers.current, expectingKey {
        throw Error.invalidEventSequence("Missing value for key")
    }
    containers.didFinishScalarValue()
  }

  private mutating func writePendingTags() {
    for tag in pendingTags {
      writeTagHeader(tag)
    }
    pendingTags.removeAll(keepingCapacity: true)
  }

  private mutating func emitBufferedMap(_ completion: MapBufferCompletion) throws {
    let encodedPairs = try completion.pairs.map { pair -> (keyBytes: Data, valueBytes: Data, order: Int) in
      let valueBytes = try Self.encodeEmitEvents(
        pair.valueEvents,
        options: options
      )
      return (keyBytes: pair.keyBytes, valueBytes: valueBytes, order: pair.order)
    }

    let orderedPairs: [(keyBytes: Data, valueBytes: Data, order: Int)]
    orderedPairs = encodedPairs.sorted {
      CBORDeterministicKeyEncoder.isOrderedBefore(
        $0.keyBytes,
        order: $0.order,
        $1.keyBytes,
        order: $1.order
      )
    }

    writePendingTags()
    writeLength(completion.expectedPairs, majorType: 0b101)
    for pair in orderedPairs {
      buffer.append(pair.keyBytes)
      buffer.append(pair.valueBytes)
    }
    try finishValue()
  }

  private func tagValue(_ tag: Value) throws -> UInt64 {
    guard case .number(let number) = tag, let tagInt: UInt64 = number.int(as: UInt64.self) else {
      throw Error.invalidTagValue
    }
    return tagInt
  }

  // MARK: - Value Encoding

  mutating func writeValue(_ value: Value) throws {
    switch value {
    case .null:
      writeNull()

    case .bool(let bool):
      writeBool(bool)

    case .number(let number):
      switch number {
      case .binary(let binary):
        switch binary {
        case .int8(let int8):
          if int8 >= 0 {
            writeUInt8(UInt8(int8))
          } else {
            writeNegativeInt(Int64(int8))
          }
        case .uint8(let uint8):
          writeUInt8(uint8)

        case .int16(let int16):
          if int16 >= 0 {
            writeUInt16(UInt16(int16))
          } else {
            writeNegativeInt(Int64(int16))
          }
        case .uint16(let uint16):
          writeUInt16(uint16)

        case .int32(let int32):
          if int32 >= 0 {
            writeUInt32(UInt32(int32))
          } else {
            writeNegativeInt(Int64(int32))
          }
        case .uint32(let uint32):
          writeUInt32(uint32)

        case .int64(let int64):
          if int64 >= 0 {
            writeVarUInt(UInt64(int64))
          } else {
            writeNegativeInt(int64)
          }
        case .uint64(let uint64):
          writeVarUInt(uint64)

        case .int128(let int128):
          try writeBignum(BigInt(int128))
        case .uint128(let uint128):
          try writeBignum(BigUInt(uint128))

        case .int(let int):
          try writeBignum(int)
        case .uint(let uint):
          try writeBignum(uint)

        case .float16(let float16):
          writeHalf(float16)
        case .float32(let float32):
          writeFloat(float32)
        case .float64(let float64):
          writeDouble(float64)

        case .decimal(let decimal):
          try writeTagged(tag: 4, value: [.number(.binary(.int64(Int64(decimal.exponent)))), .number(.binary(.int(decimal.mantissa)))])

        }

      case .text(let text):
        if text.isNaN {
          writeFloat(Float32.nan)
        } else if text.isInfinity {
          writeFloat(text.isNegative ? -Float32.infinity : Float32.infinity)
        } else if let integer = text.integer {
          if integer >= 0 {
            if integer <= UInt8.max {
              writeUInt8(UInt8(integer))
            } else if integer <= UInt16.max {
              writeUInt16(UInt16(integer))
            } else if integer <= UInt32.max {
              writeUInt32(UInt32(integer))
            } else if integer <= UInt64.max {
              writeUInt64(UInt64(integer))
            } else {
              try writeBignum(integer)
            }
          } else if integer >= Int64.min {
            writeNegativeInt(Int64(integer))
          } else {
            try writeBignum(integer)
          }
        } else if let float = text.float(as: Float16.self) {
          writeHalf(float)
        } else if let float = text.float(as: Float32.self) {
          writeFloat(float)
        } else if let float = text.float(as: Float64.self) {
          writeDouble(float)
        } else {
          try writeDecimalFraction(text.decimal)
        }
      }

    case .bytes(let data):
      writeByteString(data)

    case .string(let str):
      writeString(str)

    case .array(let array):
      try writeArray(array)

    case .object(let dict):
      try writeMap(dict)

    case .tagged(tags: let tags, value: let value):
      for tag in tags {
        guard case .number(let tagNumber) = tag, let tagInt: UInt64 = tagNumber.int() else {
          throw CBOR.Error.invalidTagType
        }
        writeTagHeader(tagInt)
      }
      try writeValue(value)
    }
  }

  mutating func writeValue(_ value: Value, tag: UInt64) throws {
    try writeTagged(tag: tag, value: value)
  }

  // MARK: - major 0: unsigned integer

  private mutating func writeLength(_ val: Int, majorType: UInt8) {
    writeVarUInt(UInt64(val), modifier: (majorType << 5))
  }

  private mutating func writeUInt8(_ val: UInt8, modifier: UInt8 = 0) {
    if val < 24 {
      buffer.append(val | modifier)
    } else {
      buffer.append(0x18 | modifier)
      buffer.append(val)
    }
  }

  private mutating func writeUInt16(_ val: UInt16, modifier: UInt8 = 0) {
    buffer.append(0x19 | modifier)
    appendBigEndian(val)
  }

  private mutating func writeUInt32(_ val: UInt32, modifier: UInt8 = 0) {
    buffer.append(0x1A | modifier)
    appendBigEndian(val)
  }

  private mutating func writeUInt64(_ val: UInt64, modifier: UInt8 = 0) {
    buffer.append(0x1B | modifier)
    appendBigEndian(val)
  }

  private mutating func writeVarUInt(_ val: UInt64, modifier: UInt8 = 0) {
    switch val {
    case let val where val <= UInt8.max: writeUInt8(UInt8(val), modifier: modifier)
    case let val where val <= UInt16.max: writeUInt16(UInt16(val), modifier: modifier)
    case let val where val <= UInt32.max: writeUInt32(UInt32(val), modifier: modifier)
    default: writeUInt64(val, modifier: modifier)
    }
  }

  // MARK: - major 1: negative integer

  private mutating func writeNegativeInt(_ val: Int64) {
    writeNegativeInt(val, modifier: 0)
  }

  private mutating func writeNegativeInt(_ val: Int64, modifier: UInt8) {
    assert(val < 0)
    writeVarUInt(~UInt64(bitPattern: val), modifier: 0b0010_0000 | modifier)
  }

  // MARK: - major 2: bytestring

  private mutating func writeByteString(_ str: Data) {
    writeLength(str.count, majorType: 0b010)
    buffer.append(str)
  }

  // MARK: - major 3: UTF8 string

  private mutating func writeString(_ str: String) {
    let len = str.utf8.count
    writeLength(len, majorType: 0b011)
    buffer.append(contentsOf: str.utf8)
  }

  // MARK: - major 4: array of data items

  private mutating func writeArray(_ array: Value.Array) throws {
    writeLength(array.count, majorType: 0b100)
    try writeArrayChunk(array)
  }

  mutating func writeArrayChunk(_ chunk: some Sequence<Value>) throws {
    for item in chunk {
      try writeValue(item)
    }
  }

  // MARK: - major 5: a map of pairs of data items

  private mutating func writeMap(_ map: Value.Object) throws {
    writeLength(map.count, majorType: 0b101)
    if options.deterministic {
      let sorted = try map.enumerated().map { order, entry in
        (keyBytes: try deterministicBytes(of: entry.key), order: order, key: entry.key, value: entry.value)
      }
      .sorted {
        CBORDeterministicKeyEncoder.isOrderedBefore(
          $0.keyBytes,
          order: $0.order,
          $1.keyBytes,
          order: $1.order
        )
      }
      for entry in sorted {
        try writeValue(entry.key)
        try writeValue(entry.value)
      }
    } else {
      try writeMapChunk(map)
    }
  }

  mutating func writeMapChunk(_ map: some Sequence<(key: Value, value: Value)>) throws {
    for (key, value) in map {
      try writeValue(key)
      try writeValue(value)
    }
  }

  // MARK: - major 6: tagged values

  private mutating func writeTagged(tag: UInt64, value: Value) throws {
    writeVarUInt(tag, modifier: 0b1100_0000)
    try writeValue(value)
  }

  // MARK: - major 7: floats, simple values, the 'break' stop code

  private mutating func writeSimpleValue(_ val: UInt8) {
    if val < 24 {
      buffer.append(0b1110_0000 | val)
    } else {
      buffer.append(0xF8)
      buffer.append(val)
    }
  }

  private mutating func writeNull() {
    buffer.append(0xF6)
  }

  private mutating func writeUndefined() {
    buffer.append(0xF7)
  }

  private mutating func writeHalf(_ val: Float16) {
    buffer.append(0xF9)
    appendBigEndian(options.deterministic && val.isNaN ? 0x7E00 : val.bitPattern)
  }

  private mutating func writeFloat(_ val: Float32) {
    if options.deterministic {
      if val.isNaN {
        return writeHalf(.nan)
      }
      let half = Float16(val)
      if Float32(half) == val {
        return writeHalf(half)
      }
    }
    buffer.append(0xFA)
    appendBigEndian(val.bitPattern)
  }

  private mutating func writeDouble(_ val: Double) {
    if options.deterministic {
      if val.isNaN {
        return writeFloat(Float32(val))
      }
      let float = Float32(val)
      if Double(float) == val {
        return writeFloat(float)
      }
    }
    buffer.append(0xFB)
    appendBigEndian(val.bitPattern)
  }

  private mutating func writeBool(_ val: Bool) {
    buffer.append(val ? 0xF5 : 0xF4)
  }

  private mutating func writeBignum(_ value: BigInt) throws {
    let bytes = value.magnitude.encode()
    try writeTagged(tag: value.isNegative ? 3 : 2, value: .bytes(Data(bytes)))
  }

  private mutating func writeBignum(_ value: BigUInt) throws {
    let bytes = value.encode()
    try writeTagged(tag: 2, value: .bytes(Data(bytes)))
  }

  private mutating func writeDecimalFraction(_ value: BigDecimal) throws {
    let exponent = value.exponent
    let mantissa = value.mantissa
    try writeTagged(tag: CBORStructure.Tags.decimalFractionTag, value: [.number(.binary(.int64(Int64(exponent)))), .number(.binary(.int(mantissa)))])
  }

  // MARK: - Indefinite length items

  mutating func writeIndefiniteStart(for type: CBORStreamItemType) {
    buffer.append(type.rawValue)
  }

  mutating func writeIndefiniteEnd() {
    buffer.append(0xFF)
  }

  mutating func writeTagHeader(_ tag: UInt64) {
    writeVarUInt(tag, modifier: 0b1100_0000)
  }

  private mutating func appendBigEndian<T: FixedWidthInteger>(_ int: T) {
    withUnsafeBytes(of: int.bigEndian) { ptr in
      buffer.append(contentsOf: ptr)
    }
  }

  private func deterministicBytes(of value: Value) throws -> Data {
    return try CBORDeterministicKeyEncoder.encode(value)
  }

}

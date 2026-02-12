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

protocol CBORByteSink: AnyObject {
  func writeByte(_ byte: UInt8) throws
  func writeBytes(_ ptr: UnsafeBufferPointer<UInt8>) throws
  func writeBytes(_ data: Data) throws
}

final class CBOREncoder: FormatStreamEncoder {

  enum Error: Swift.Error {
    case invalidEventSequence(String)
    case incompleteCBOR
    case alreadyFinished
    case invalidTagValue
  }

  struct Options: Sendable {
    var deterministic: Bool
    var deterministicMode: DeterministicMode

    init(deterministic: Bool = false, deterministicMode: DeterministicMode = .none) {
      self.deterministic = deterministic
      self.deterministicMode = deterministicMode
    }
  }

  enum DeterministicMode: Sendable, Equatable {
    case none
    case assumeSortedKeys
    case buffered(maxPairs: Int, maxBytes: Int)
    case strict(maxPairs: Int, maxBytes: Int)
  }

  private enum RootState {
    case expectingValue
    case complete
  }

  private enum ContainerState {
    case array(remaining: Int?)
    case object(remaining: Int?, expectingKey: Bool)
  }

  private struct ValueEventSequenceBuilder {
    var events: [ValueEvent] = []
    private var depth = 0
    private(set) var isComplete = false

    mutating func append(_ event: ValueEvent) throws {
      events.append(event)
      switch event {
      case .beginArray, .beginObject:
        depth += 1
      case .endArray, .endObject:
        depth -= 1
        if depth < 0 {
          throw Error.invalidEventSequence("Unexpected container end")
        }
        if depth == 0 {
          isComplete = true
        }
      case .scalar:
        if depth == 0 {
          isComplete = true
        }
      case .key:
        if depth == 0 {
          throw Error.invalidEventSequence("Key outside object")
        }
      default:
        break
      }
    }
  }

  private struct BufferedPair {
    let key: Value
    let keyBytes: Data
    let valueEvents: [ValueEvent]
    let order: Int
  }

  private struct MapBufferCompletion {
    let expectedPairs: Int
    let pairs: [BufferedPair]
    let mode: DeterministicMode
  }

  private struct MapBuffer {
    let expectedPairs: Int
    let mode: DeterministicMode
    var pairs: [BufferedPair] = []
    var pendingKey: Value?
    var currentValue: ValueEventSequenceBuilder?

    mutating func handle(_ event: ValueEvent) throws -> MapBufferCompletion? {
      if var builder = currentValue {
        try builder.append(event)
        currentValue = builder
        if builder.isComplete {
          try finalizePair()
        }
        return nil
      }

      switch event {
      case .key(let key):
        guard pendingKey == nil else {
          throw Error.invalidEventSequence("Missing value for key")
        }
        pendingKey = key
        return nil
      case .endObject:
        guard pendingKey == nil else {
          throw Error.invalidEventSequence("Missing value for key")
        }
        guard pairs.count == expectedPairs else {
          throw Error.invalidEventSequence("Missing map entries")
        }
        return MapBufferCompletion(expectedPairs: expectedPairs, pairs: pairs, mode: mode)
      default:
        guard pendingKey != nil else {
          throw Error.invalidEventSequence("Value without key")
        }
        var builder = ValueEventSequenceBuilder()
        try builder.append(event)
        currentValue = builder
        if builder.isComplete {
          try finalizePair()
        }
        return nil
      }
    }

    private mutating func finalizePair() throws {
      guard let key = pendingKey, let builder = currentValue else { return }
      let keyBytes = try CBOREncoder.encodeValue(key, deterministic: true)
      let pair = BufferedPair(key: key, keyBytes: keyBytes, valueEvents: builder.events, order: pairs.count)
      pairs.append(pair)
      pendingKey = nil
      currentValue = nil
      if pairs.count > expectedPairs {
        throw Error.invalidEventSequence("Too many map entries")
      }
    }
  }

  private let stream: CBORByteSink
  private var bufferStream: CBORByteBuffer?
  private let options: Options

  private var pendingOffset = 0
  private var rootState: RootState = .expectingValue
  private var containers: [ContainerState] = []
  private var pendingTags: [UInt64] = []
  private var finished = false
  private var pendingEvent = false
  private var mapBuffer: MapBuffer?

  var format: Format { CBOR.format }

  init(sink: CBORByteSink, options: Options = Options()) {
    self.stream = sink
    self.options = options
  }

  init(options: Options = Options()) {
    let bufferStream = CBORByteBuffer()
    self.stream = bufferStream
    self.bufferStream = bufferStream
    self.options = options
  }

  static func encodeValue(_ value: Value, deterministic: Bool) throws -> Data {
    let buffer = CBORByteBuffer()
    let encoder = CBOREncoder(sink: buffer, options: Options(deterministic: deterministic, deterministicMode: .none))
    try encoder.writeValue(value)
    return buffer.data
  }

  // MARK: - Event Encoding

  func writeEvent(_ event: ValueEvent) throws {
    guard !finished else { throw Error.alreadyFinished }
    if var buffer = mapBuffer {
      if let completion = try buffer.handle(event) {
        mapBuffer = nil
        try emitBufferedMap(completion)
      } else {
        mapBuffer = buffer
      }
      return
    }

    if case .beginObject(let count) = event, options.deterministicMode != .none, options.deterministicMode != .assumeSortedKeys {
      switch options.deterministicMode {
      case .buffered(let maxPairs, _):
        if let count, count <= maxPairs {
          try prepareForValue(isKey: false)
          mapBuffer = MapBuffer(expectedPairs: count, mode: options.deterministicMode)
          return
        }
      case .strict(let maxPairs, _):
        guard let count else {
          throw Error.invalidEventSequence("Indefinite map not allowed in deterministic mode")
        }
        guard count <= maxPairs else {
          throw Error.invalidEventSequence("Map exceeds deterministic limit")
        }
        try prepareForValue(isKey: false)
        mapBuffer = MapBuffer(expectedPairs: count, mode: options.deterministicMode)
        return
      case .assumeSortedKeys, .none:
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

    case .key(let key):
      try prepareForValue(isKey: true)
      try writePendingTags()
      try writeValue(key)
      try setObjectExpectingValue()

    case .scalar(let value):
      try prepareForValue(isKey: false)
      try writePendingTags()
      try writeValue(value)
      try finishValue()

    case .beginArray(let count):
      try prepareForValue(isKey: false)
      try writePendingTags()
      if let count {
        try writeLength(count, majorType: 0b100)
        containers.append(.array(remaining: count))
      } else {
        try writeIndefiniteStart(for: .array)
        containers.append(.array(remaining: nil))
      }

    case .endArray:
      guard pendingTags.isEmpty else {
        throw Error.invalidEventSequence("Tag without value")
      }
      guard case .array(let remaining) = containers.popLast() else {
        throw Error.invalidEventSequence("Unexpected endArray")
      }
      if let remaining, remaining != 0 {
        throw Error.invalidEventSequence("Missing array values")
      }
      if remaining == nil {
        try writeIndefiniteEnd()
      }
      try finishValue()

    case .beginObject(let count):
      try prepareForValue(isKey: false)
      try writePendingTags()
      if let count {
        try writeLength(count, majorType: 0b101)
        containers.append(.object(remaining: count, expectingKey: true))
      } else {
        try writeIndefiniteStart(for: .map)
        containers.append(.object(remaining: nil, expectingKey: true))
      }

    case .endObject:
      guard pendingTags.isEmpty else {
        throw Error.invalidEventSequence("Tag without value")
      }
      guard case .object(let remaining, let expectingKey) = containers.popLast() else {
        throw Error.invalidEventSequence("Unexpected endObject")
      }
      guard expectingKey else {
        throw Error.invalidEventSequence("Missing value for key")
      }
      if let remaining, remaining != 0 {
        throw Error.invalidEventSequence("Missing object values")
      }
      if remaining == nil {
        try writeIndefiniteEnd()
      }
      try finishValue()
    }
  }

  func finishEvents() throws {
    guard mapBuffer == nil else {
      throw Error.incompleteCBOR
    }
    guard containers.isEmpty, pendingTags.isEmpty, rootState == .complete else {
      throw Error.incompleteCBOR
    }
  }

  private func prepareForValue(isKey: Bool) throws {
    if containers.isEmpty {
      guard rootState == .expectingValue else {
        throw Error.invalidEventSequence("Unexpected value after root")
      }
      return
    }
    switch containers[containers.count - 1] {
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

  private func setObjectExpectingValue() throws {
    guard case .object(let remaining, let expectingKey) = containers.popLast() else {
      throw Error.invalidEventSequence("Key outside map")
    }
    guard expectingKey else {
      throw Error.invalidEventSequence("Unexpected key")
    }
    containers.append(.object(remaining: remaining, expectingKey: false))
  }

  private func finishValue() throws {
    if containers.isEmpty {
      rootState = .complete
      return
    }
    guard let container = containers.popLast() else {
      return
    }
    switch container {
    case .array(let remaining):
      if let remaining {
        let newRemaining = remaining - 1
        guard newRemaining >= 0 else {
          throw Error.invalidEventSequence("Too many array values")
        }
        containers.append(.array(remaining: newRemaining))
      } else {
        containers.append(.array(remaining: nil))
      }
    case .object(let remaining, let expectingKey):
      guard !expectingKey else {
        throw Error.invalidEventSequence("Missing value for key")
      }
      if let remaining {
        let newRemaining = remaining - 1
        guard newRemaining >= 0 else {
          throw Error.invalidEventSequence("Too many object values")
        }
        containers.append(.object(remaining: newRemaining, expectingKey: true))
      } else {
        containers.append(.object(remaining: nil, expectingKey: true))
      }
    }
  }

  private func writePendingTags() throws {
    for tag in pendingTags {
      try writeTagHeader(tag)
    }
    pendingTags.removeAll(keepingCapacity: true)
  }

  private func emitBufferedMap(_ completion: MapBufferCompletion) throws {
    let encodedPairs = try completion.pairs.map { pair -> (keyBytes: Data, valueBytes: Data, order: Int) in
      let valueBytes = try encodeValueEvents(pair.valueEvents)
      return (keyBytes: pair.keyBytes, valueBytes: valueBytes, order: pair.order)
    }

    let totalBytes = encodedPairs.reduce(0) { $0 + $1.keyBytes.count + $1.valueBytes.count }
    let useOriginalOrder: Bool

    switch completion.mode {
    case .none:
      useOriginalOrder = true
    case .assumeSortedKeys:
      useOriginalOrder = true
    case .buffered(_, let maxBytes):
      useOriginalOrder = totalBytes > maxBytes
    case .strict(_, let maxBytes):
      if totalBytes > maxBytes {
        throw Error.invalidEventSequence("Deterministic map exceeds max bytes")
      }
      useOriginalOrder = false
    }

    let orderedPairs: [(keyBytes: Data, valueBytes: Data, order: Int)]
    if useOriginalOrder {
      orderedPairs = encodedPairs.sorted { $0.order < $1.order }
    } else {
      orderedPairs = encodedPairs.sorted {
        if $0.keyBytes.count != $1.keyBytes.count {
          return $0.keyBytes.count < $1.keyBytes.count
        }
        return $0.keyBytes.lexicographicallyPrecedes($1.keyBytes)
      }
    }

    try writePendingTags()
    try writeLength(completion.expectedPairs, majorType: 0b101)
    for pair in orderedPairs {
      try stream.writeBytes(pair.keyBytes)
      try stream.writeBytes(pair.valueBytes)
    }
    try finishValue()
  }

  private func encodeValueEvents(_ events: [ValueEvent]) throws -> Data {
    let encoder = CBOREncoder(options: Options(deterministic: false, deterministicMode: .none))
    var buffer = FormatStreamEncoderBuffer(encoder: encoder)
    return try buffer.encode(events: events)
  }

  private func tagValue(_ tag: Value) throws -> UInt64 {
    guard case .number(let number) = tag, let tagInt: UInt64 = number.int(as: UInt64.self) else {
      throw Error.invalidTagValue
    }
    return tagInt
  }

  // MARK: - Value Encoding

  func writeValue(_ value: Value) throws {
    switch value {
    case .null:
      try writeNull()

    case .bool(let bool):
      try writeBool(bool)

    case .number(let number):
      switch number {
      case let binary as Value.BinaryNumber:
        switch binary {
        case .int8(let int8):
          if int8 >= 0 {
            try writeUInt8(UInt8(int8))
          } else {
            try writeNegativeInt(Int64(int8))
          }
        case .uint8(let uint8):
          try writeUInt8(uint8)

        case .int16(let int16):
          if int16 >= 0 {
            try writeUInt16(UInt16(int16))
          } else {
            try writeNegativeInt(Int64(int16))
          }
        case .uint16(let uint16):
          try writeUInt16(uint16)

        case .int32(let int32):
          if int32 >= 0 {
            try writeUInt32(UInt32(int32))
          } else {
            try writeNegativeInt(Int64(int32))
          }
        case .uint32(let uint32):
          try writeUInt32(uint32)

        case .int64(let int64):
          if int64 >= 0 {
            try writeVarUInt(UInt64(int64))
          } else {
            try writeNegativeInt(int64)
          }
        case .uint64(let uint64):
          try writeVarUInt(uint64)

        case .int128(let int128):
          try writeBignum(BigInt(int128))
        case .uint128(let uint128):
          try writeBignum(BigUInt(uint128))

        case .int(let int):
          try writeBignum(int)
        case .uint(let uint):
          try writeBignum(uint)

        case .float16(let float16):
          try writeHalf(float16)
        case .float32(let float32):
          try writeFloat(float32)
        case .float64(let float64):
          try writeDouble(float64)

        case .decimal(let decimal):
          try writeTagged(tag: 4, value: [.number(decimal.exponent), .number(decimal.mantissa)])

        @unknown default:
          fatalError("Unknown BinaryNumber case")
        }

      case let text as Value.TextNumber:
        if text.isNaN {
          try writeFloat(Float32.nan)
        } else if text.isInfinity {
          try writeFloat(text.isNegative ? -Float32.infinity : Float32.infinity)
        } else if let integer = text.integer {
          if integer >= 0 {
            if integer <= UInt8.max {
              try writeUInt8(UInt8(integer))
            } else if integer <= UInt16.max {
              try writeUInt16(UInt16(integer))
            } else if integer <= UInt32.max {
              try writeUInt32(UInt32(integer))
            } else if integer <= UInt64.max {
              try writeUInt64(UInt64(integer))
            } else {
              try writeBignum(integer)
            }
          } else if integer >= Int64.min {
            try writeNegativeInt(Int64(integer))
          } else {
            try writeBignum(integer)
          }
        } else if let float = text.float(as: Float16.self) {
          try writeHalf(float)
        } else if let float = text.float(as: Float32.self) {
          try writeFloat(float)
        } else if let float = text.float(as: Float64.self) {
          try writeDouble(float)
        } else {
          try writeDecimalFraction(text.decimal)
        }

      default:
        fatalError("Unknown Number type")
      }

    case .bytes(let data):
      try writeByteString(data)

    case .string(let str):
      try writeString(str)

    case .array(let array):
      try writeArray(array)

    case .object(let dict):
      try writeMap(dict)

    case .tagged(tag: let tag, value: let value):
      guard case .number(let tagNumber) = tag, let tagInt: UInt64 = tagNumber.int() else {
        throw CBOR.Error.invalidTagType
      }
      try writeTagged(tag: tagInt, value: value)
    }
  }

  func writeValue(_ value: Value, tag: UInt64) throws {
    try writeTagged(tag: tag, value: value)
  }

  // MARK: - major 0: unsigned integer

  private func writeLength(_ val: Int, majorType: UInt8) throws {
    try writeVarUInt(UInt64(val), modifier: (majorType << 5))
  }

  private func writeUInt8(_ val: UInt8, modifier: UInt8 = 0) throws {
    if val < 24 {
      try stream.writeByte(val | modifier)
    } else {
      try stream.writeByte(0x18 | modifier)
      try stream.writeByte(val)
    }
  }

  private func writeUInt16(_ val: UInt16, modifier: UInt8 = 0) throws {
    try stream.writeByte(0x19 | modifier)
    try writeInt(val)
  }

  private func writeUInt32(_ val: UInt32, modifier: UInt8 = 0) throws {
    try stream.writeByte(0x1A | modifier)
    try writeInt(val)
  }

  private func writeUInt64(_ val: UInt64, modifier: UInt8 = 0) throws {
    try stream.writeByte(0x1B | modifier)
    try writeInt(val)
  }

  private func writeVarUInt(_ val: UInt64, modifier: UInt8 = 0) throws {
    switch val {
    case let val where val <= UInt8.max: try writeUInt8(UInt8(val), modifier: modifier)
    case let val where val <= UInt16.max: try writeUInt16(UInt16(val), modifier: modifier)
    case let val where val <= UInt32.max: try writeUInt32(UInt32(val), modifier: modifier)
    default: try writeUInt64(val, modifier: modifier)
    }
  }

  // MARK: - major 1: negative integer

  private func writeNegativeInt(_ val: Int64) throws {
    try writeNegativeInt(val, modifier: 0)
  }

  private func writeNegativeInt(_ val: Int64, modifier: UInt8) throws {
    assert(val < 0)
    try writeVarUInt(~UInt64(bitPattern: val), modifier: 0b0010_0000 | modifier)
  }

  // MARK: - major 2: bytestring

  private func writeByteString(_ str: Data) throws {
    try writeLength(str.count, majorType: 0b010)
    try stream.writeBytes(str)
  }

  // MARK: - major 3: UTF8 string

  private func writeString(_ str: String) throws {
    let len = str.utf8.count
    try writeLength(len, majorType: 0b011)
    try str.withCString { ptr in
      try ptr.withMemoryRebound(to: UInt8.self, capacity: len) { ptr in
        try stream.writeBytes(UnsafeBufferPointer(start: ptr, count: len))
      }
    }
  }

  // MARK: - major 4: array of data items

  private func writeArray(_ array: Value.Array) throws {
    try writeLength(array.count, majorType: 0b100)
    try writeArrayChunk(array)
  }

  func writeArrayChunk(_ chunk: some Sequence<Value>) throws {
    for item in chunk {
      try writeValue(item)
    }
  }

  // MARK: - major 5: a map of pairs of data items

  private func writeMap(_ map: Value.Object) throws {
    try writeLength(map.count, majorType: 0b101)
    if options.deterministic {
      try map.map { (try deterministicBytes(of: $0), ($0, $1)) }
        .sorted { (itemA, itemB) in itemA.0.lexicographicallyPrecedes(itemB.0) }
        .map { $1 }
        .forEach { key, value in
          try writeValue(key)
          try writeValue(value)
        }
    } else {
      try writeMapChunk(map)
    }
  }

  func writeMapChunk(_ map: some Sequence<(key: Value, value: Value)>) throws {
    for (key, value) in map {
      try writeValue(key)
      try writeValue(value)
    }
  }

  // MARK: - major 6: tagged values

  private func writeTagged(tag: UInt64, value: Value) throws {
    try writeVarUInt(tag, modifier: 0b1100_0000)
    try writeValue(value)
  }

  // MARK: - major 7: floats, simple values, the 'break' stop code

  private func writeSimpleValue(_ val: UInt8) throws {
    if val < 24 {
      try stream.writeByte(0b1110_0000 | val)
    } else {
      try stream.writeByte(0xF8)
      try stream.writeByte(val)
    }
  }

  private func writeNull() throws {
    try stream.writeByte(0xF6)
  }

  private func writeUndefined() throws {
    try stream.writeByte(0xF7)
  }

  private func writeHalf(_ val: Float16) throws {
    try stream.writeByte(0xF9)
    try writeInt(val.bitPattern)
  }

  private func writeFloat(_ val: Float32) throws {
    if options.deterministic {
      if val.isNaN {
        return try writeHalf(.nan)
      }
      let half = Float16(val)
      if Float32(half) == val {
        return try writeHalf(half)
      }
    }
    try stream.writeByte(0xFA)
    try writeInt(val.bitPattern)
  }

  private func writeDouble(_ val: Double) throws {
    if options.deterministic {
      if val.isNaN {
        return try writeFloat(Float32(val))
      }
      let float = Float32(val)
      if Double(float) == val {
        return try writeFloat(float)
      }
    }
    try stream.writeByte(0xFB)
    try writeInt(val.bitPattern)
  }

  private func writeBool(_ val: Bool) throws {
    try stream.writeByte(val ? 0xF5 : 0xF4)
  }

  private func writeBignum(_ value: BigInt) throws {
    let bytes = value.magnitude.encode()
    try writeTagged(tag: value.isNegative ? 3 : 2, value: .bytes(Data(bytes)))
  }

  private func writeBignum(_ value: BigUInt) throws {
    let bytes = value.encode()
    try writeTagged(tag: 2, value: .bytes(Data(bytes)))
  }

  private func writeDecimalFraction(_ value: BigDecimal) throws {
    let exponent = value.exponent
    let mantissa = value.mantissa
    try writeTagged(tag: CBORStructure.Tags.decimalFractionTag, value: [.number(exponent), .number(mantissa)])
  }

  // MARK: - Indefinite length items

  func writeIndefiniteStart(for type: CBORStreamItemType) throws {
    try stream.writeByte(type.rawValue)
  }

  func writeIndefiniteEnd() throws {
    try stream.writeByte(0xFF)
  }

  func writeTagHeader(_ tag: UInt64) throws {
    try writeVarUInt(tag, modifier: 0b1100_0000)
  }

  private func writeInt<T: FixedWidthInteger>(_ int: T) throws {
    try withUnsafeBytes(of: int.bigEndian) { ptr in
      try stream.writeBytes(ptr.bindMemory(to: UInt8.self))
    }
  }

  private func deterministicBytes(of value: Value) throws -> Data {
    return try Self.encodeValue(value, deterministic: true)
  }

  // MARK: - FormatStreamEncoder

  func encode(_ event: ValueEvent, output: inout OutputSpan<UInt8>) throws -> FormatStreamEncodeStatus {
    if pendingEvent {
      let pendingStatus = drainPending(into: &output)
      if pendingStatus == .needMoreOutputSpace {
        return pendingStatus
      }
      pendingEvent = false
      return .producedOutput
    }

    let pendingStatus = drainPending(into: &output)
    if pendingStatus == .needMoreOutputSpace {
      return pendingStatus
    }

    try writeEvent(event)
    let status = drainPending(into: &output)
    if status == .needMoreOutputSpace {
      pendingEvent = true
    }
    return status
  }

  func finish(output: inout OutputSpan<UInt8>) throws -> FormatStreamEncodeStatus {
    let pendingStatus = drainPending(into: &output)
    if pendingStatus == .needMoreOutputSpace {
      return pendingStatus
    }

    if finished {
      let finalStatus = drainPending(into: &output)
      return finalStatus == .needMoreOutputSpace ? finalStatus : .endOfStream
    }
    try finishEvents()
    finished = true

    let finalStatus = drainPending(into: &output)
    return finalStatus == .needMoreOutputSpace ? finalStatus : .endOfStream
  }

  private func drainPending(into output: inout OutputSpan<UInt8>) -> FormatStreamEncodeStatus {
    guard let bufferStream else { return .producedOutput }

    let data = bufferStream.data
    guard pendingOffset < data.count else {
      bufferStream.data.removeAll(keepingCapacity: true)
      pendingOffset = 0
      return .producedOutput
    }

    guard !output.isFull else { return .needMoreOutputSpace }

    while pendingOffset < data.count && !output.isFull {
      output.append(data[pendingOffset])
      pendingOffset += 1
    }

    if pendingOffset >= data.count {
      bufferStream.data.removeAll(keepingCapacity: true)
      pendingOffset = 0
      return .producedOutput
    }

    return .needMoreOutputSpace
  }
}

final class CBORByteBuffer: CBORByteSink {
  var data = Data()

  func writeByte(_ byte: UInt8) throws {
    data.append(byte)
  }

  func writeBytes(_ ptr: UnsafeBufferPointer<UInt8>) throws {
    guard let baseAddress = ptr.baseAddress else {
      return
    }
    data.append(baseAddress, count: ptr.count)
  }

  func writeBytes(_ data: Data) throws {
    self.data.append(data)
  }

  func writeInt<T>(_ int: T) throws where T: FixedWidthInteger {
    try withUnsafeBytes(of: int.bigEndian) { ptr in
      try writeBytes(ptr.bindMemory(to: UInt8.self))
    }
  }
}

extension CBOREncoder.DeterministicMode {
  init(_ mode: CBORStreamWriter.DeterministicMode) {
    switch mode {
    case .none:
      self = .none
    case .assumeSortedKeys:
      self = .assumeSortedKeys
    case .buffered(let maxPairs, let maxBytes):
      self = .buffered(maxPairs: maxPairs, maxBytes: maxBytes)
    case .strict(let maxPairs, let maxBytes):
      self = .strict(maxPairs: maxPairs, maxBytes: maxBytes)
    }
  }
}

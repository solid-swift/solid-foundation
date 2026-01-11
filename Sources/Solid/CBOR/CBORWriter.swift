//
//  CBORWriter.swift
//  PotentCodables
//
//  Copyright © 2021 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import SolidData
import SolidNumeric
import Foundation


public struct CBORWriter {

  public struct Options {
    public var deterministic: Bool = false

    public init(deterministic: Bool = false) {
      self.deterministic = deterministic
    }
  }

  public struct ArrayStream: ~Copyable {
    private var writer: CBORWriter

    private init(writer: CBORWriter) {
      self.writer = writer
    }

    public func encode(_ value: Value) throws {
      try writer.encode(value)
    }

    public func encode(_ values: some Sequence<Value>) throws {
      try writer.encodeArrayChunk(values)
    }

    public consuming func end() throws {
      try writer.encodeIndefiniteEnd()
    }
  }

  public struct MapStream: ~Copyable {
    private var writer: CBORWriter

    private init(writer: CBORWriter) {
      self.writer = writer
    }

    public func encode(_ key: Value, _ value: Value) throws {
      try writer.encode(key)
      try writer.encode(value)
    }

    public func encode(_ value: Value.Object) throws {
      try writer.encodeMapChunk(value.elements)
    }

    public func encode(_ values: some Sequence<(key: Value, value: Value)>) throws {
      try writer.encodeMapChunk(values)
    }

    public func encode(_ values: some Sequence<(Value, Value)>) throws {
      try writer.encodeMapChunk(values.lazy.map { ($0, $1) })
    }

    public consuming func end() throws {
      try writer.encodeIndefiniteEnd()
    }
  }

  public enum StreamableItemType: UInt8 {
    case map = 0xBF
    case array = 0x9F
    case string = 0x7F
    case byteString = 0x5F
  }

  private(set) var stream: CBOROutputStream
  private let options: Options

  public init(stream: CBOROutputStream, options: Options = Options()) {
    self.stream = stream
    self.options = options
  }

  /// Encodes a single CBOR item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  public func encode(_ value: Value) throws {
    switch value {
    case .null:
      try encodeNull()

    case .bool(let bool):
      try encodeBool(bool)

    case .number(let number):
      switch number {
      case let binary as Value.BinaryNumber:
        switch binary {
        case .int8(let int8):
          if int8 >= 0 {
            try encodeUInt8(UInt8(int8))
          } else {
            try encodeNegativeInt(Int64(int8))
          }
        case .uint8(let uint8):
          try encodeUInt8(uint8)

        case .int16(let int16):
          if int16 >= 0 {
            try encodeUInt16(UInt16(int16))
          } else {
            try encodeNegativeInt(Int64(int16))
          }
        case .uint16(let uint16):
          try encodeUInt16(uint16)

        case .int32(let int32):
          if int32 >= 0 {
            try encodeUInt32(UInt32(int32))
          } else {
            try encodeNegativeInt(Int64(int32))
          }
        case .uint32(let uint32):
          try encodeUInt32(uint32)

        case .int64(let int64):
          if int64 >= 0 {
            try encodeUInt64(UInt64(int64))
          } else {
            try encodeNegativeInt(int64)
          }
        case .uint64(let uint64):
          try encodeUInt64(uint64)

        case .int128(let int128):
          try encodeBignum(BigInt(int128))
        case .uint128(let uint128):
          try encodeBignum(BigInt(uint128))

        case .int(let int):
          try encodeBignum(int)
        case .uint(let uint):
          try encodeBignum(uint)

        case .float16(let float16):
          try encodeHalf(float16)
        case .float32(let float32):
          try encodeFloat(float32)
        case .float64(let float64):
          try encodeDouble(float64)

        case .decimal(let decimal):
          try encodeTagged(tag: 4, value: [.number(decimal.exponent), .number(decimal.mantissa)])

        @unknown default:
          fatalError("Unknown BinaryNumber case")
        }

      case let text as Value.TextNumber:
        if text.isNaN {
          try encodeFloat(Float32.nan)
        } else if text.isInfinity {
          try encodeFloat(text.isNegative ? -Float32.infinity : Float32.infinity)
        } else if let integer = text.integer {
          if integer >= 0 {
            if integer <= UInt8.max {
              try encodeUInt8(UInt8(integer))
            } else if integer <= UInt16.max {
              try encodeUInt16(UInt16(integer))
            } else if integer <= UInt32.max {
              try encodeUInt32(UInt32(integer))
            } else if integer <= UInt64.max {
              try encodeUInt64(UInt64(integer))
            } else {
              try encodeBignum(integer)
            }
          } else if integer >= Int64.min {
            try encodeNegativeInt(Int64(integer))
          } else {
            try encodeBignum(integer)
          }
        } else if let float = text.float(as: Float16.self) {
          try encodeHalf(float)
        } else if let float = text.float(as: Float32.self) {
          try encodeFloat(float)
        } else if let float = text.float(as: Float64.self) {
          try encodeDouble(float)
        } else {
          try encodeDecimalFraction(text.decimal)
        }

      default:
        fatalError("Unknown Number type")
      }

    case .bytes(let data):
      try encodeByteString(data)

    case .string(let str):
      try encodeString(str)

    case .array(let array):
      try encodeArray(array)

    case .object(let dict):
      try encodeMap(dict)

    case .tagged(tag: let tag, value: let value):
      guard case .number(let tagNumber) = tag, let tagInt: UInt64 = tagNumber.int() else {
        throw CBOR.Error.invalidTagType
      }
      try encodeTagged(tag: tagInt, value: value)
    }
  }

  public func encode(_ value: Value, tag: UInt64) throws {
    try encodeTagged(tag: tag, value: value)
  }

  /// Encodes any signed/unsigned integer, `or`ing `majorType` and
  /// `additional` data with first byte.
  private func encodeLength(_ val: Int, majorType: UInt8) throws {
    try encodeVarUInt(UInt64(val), modifier: (majorType << 5))
  }

  // MARK: - major 0: unsigned integer

  /// Encodes an 8bit unsigned integer, `or`ing `modifier` with first byte.
  private func encodeUInt8(_ val: UInt8, modifier: UInt8 = 0) throws {
    if val < 24 {
      try stream.writeByte(val | modifier)
    } else {
      try stream.writeByte(0x18 | modifier)
      try stream.writeByte(val)
    }
  }

  /// Encodes a 16bit unsigned integer, `or`ing `modifier` with first byte.
  private func encodeUInt16(_ val: UInt16, modifier: UInt8 = 0) throws {
    try stream.writeByte(0x19 | modifier)
    try stream.writeInt(val)
  }

  /// Encodes a 32bit unsigned integer, `or`ing `modifier` with first byte.
  private func encodeUInt32(_ val: UInt32, modifier: UInt8 = 0) throws {
    try stream.writeByte(0x1A | modifier)
    try stream.writeInt(val)
  }

  /// Encodes a 64bit unsigned integer, `or`ing `modifier` with first byte.
  private func encodeUInt64(_ val: UInt64, modifier: UInt8 = 0) throws {
    try stream.writeByte(0x1B | modifier)
    try stream.writeInt(val)
  }

  /// Encodes any unsigned integer, `or`ing `modifier` with first byte.
  private func encodeVarUInt(_ val: UInt64, modifier: UInt8 = 0) throws {
    switch val {
    case let val where val <= UInt8.max: try encodeUInt8(UInt8(val), modifier: modifier)
    case let val where val <= UInt16.max: try encodeUInt16(UInt16(val), modifier: modifier)
    case let val where val <= UInt32.max: try encodeUInt32(UInt32(val), modifier: modifier)
    default: try encodeUInt64(val, modifier: modifier)
    }
  }

  // MARK: - major 1: negative integer

  /// Encodes any negative integer item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func encodeNegativeInt(_ val: Int64) throws {
    try encodeNegativeInt(val, modifier: 0)
  }

  private func encodeNegativeInt(_ val: Int64, modifier: UInt8) throws {
    assert(val < 0)
    try encodeVarUInt(~UInt64(bitPattern: val), modifier: 0b0010_0000 | modifier)
  }

  // MARK: - major 2: bytestring

  /// Encodes provided data as a byte string item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func encodeByteString(_ str: Data) throws {
    try encodeLength(str.count, majorType: 0b010)
    try stream.writeBytes(str)
  }

  // MARK: - major 3: UTF8 string

  /// Encodes provided data as a UTF-8 string item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func encodeString(_ str: String) throws {
    let len = str.utf8.count
    try encodeLength(len, majorType: 0b011)
    try str.withCString { ptr in
      try ptr.withMemoryRebound(to: UInt8.self, capacity: len) { ptr in
        try stream.writeBytes(UnsafeBufferPointer(start: ptr, count: len))
      }
    }
  }

  // MARK: - major 4: array of data items

  /// Encodes an array of CBOR items.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func encodeArray(_ array: Value.Array) throws {
    try encodeLength(array.count, majorType: 0b100)
    try encodeArrayChunk(array)
  }

  /// Encodes an array chunk of CBOR items.
  ///
  /// - Note: This is specifically for use when creating
  /// indefinite arrays; see `encodeStreamStart` & `encodeStreamEnd`.
  /// Any number of chunks can be encoded in an indefinite array.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func encodeArrayChunk(_ chunk: some Sequence<Value>) throws {
    for item in chunk {
      try encode(item)
    }
  }

  // MARK: - major 5: a map of pairs of data items

  /// Encodes a map of CBOR item pairs.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func encodeMap(_ map: Value.Object) throws {
    try encodeLength(map.count, majorType: 0b101)
    if options.deterministic {
      try map.map { (try deterministicBytes(of: $0), ($0, $1)) }
        .sorted { (itemA, itemB) in itemA.0.lexicographicallyPrecedes(itemB.0) }
        .map { $1 }
        .forEach { key, value in
          try encode(key)
          try encode(value)
        }
    } else {
      try encodeMapChunk(map)
    }
  }

  /// Encodes a map chunk of CBOR item pairs.
  ///
  /// - Note: This is specifically for use when creating
  /// indefinite maps; see `encodeStreamStart` & `encodeStreamEnd`.
  /// Any number of chunks can be encoded in an indefinite map.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func encodeMapChunk(_ map: some Sequence<(key: Value, value: Value)>) throws {
    for (key, value) in map {
      try encode(key)
      try encode(value)
    }
  }

  // MARK: - major 6: tagged values

  /// Encodes a tagged CBOR item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func encodeTagged(tag: UInt64, value: Value) throws {
    try encodeVarUInt(tag, modifier: 0b1100_0000)
    try encode(value)
  }

  // MARK: - major 7: floats, simple values, the 'break' stop code

  private func encodeSimpleValue(_ val: UInt8) throws {
    if val < 24 {
      try stream.writeByte(0b1110_0000 | val)
    } else {
      try stream.writeByte(0xF8)
      try stream.writeByte(val)
    }
  }

  /// Encodes CBOR null item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func encodeNull() throws {
    try stream.writeByte(0xF6)
  }

  /// Encodes CBOR undefined item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func encodeUndefined() throws {
    try stream.writeByte(0xF7)
  }

  /// Encodes Half item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func encodeHalf(_ val: Float16) throws {
    try stream.writeByte(0xF9)
    try stream.writeInt(val.bitPattern)
  }

  /// Encodes Float item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func encodeFloat(_ val: Float32) throws {
    if options.deterministic {
      if val.isNaN {
        return try encodeHalf(.nan)
      }
      let half = Float16(val)
      if Float32(half) == val {
        return try encodeHalf(half)
      }
    }
    try stream.writeByte(0xFA)
    try stream.writeInt(val.bitPattern)
  }

  /// Encodes Double item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func encodeDouble(_ val: Double) throws {
    if options.deterministic {
      if val.isNaN {
        return try encodeFloat(Float32(val))
      }
      let float = Float32(val)
      if Double(float) == val {
        return try encodeFloat(float)
      }
    }
    try stream.writeByte(0xFB)
    try stream.writeInt(val.bitPattern)
  }

  /// Encodes Bool item.
  ///
  /// - Throws: A `Swift.Error`: If any I/O error occurs
  ///
  private func encodeBool(_ val: Bool) throws {
    try stream.writeByte(val ? 0xF5 : 0xF4)
  }

  /// Encodes a bignum value.
  ///
  /// - Parameter value: The bignum value to encode
  /// - Throws: A `Swift.Error` If any I/O error occurs
  ///
  private func encodeBignum(_ value: BigInt) throws {

    // Get bytes magnitude (absolute value) in big-endian order
    let bytes = value.magnitude.encode()

    // Encode with appropriate tag
    try encodeTagged(tag: value.isNegative ? 3 : 2, value: .bytes(Data(bytes)))
  }

  /// Encodes a bignum value.
  ///
  /// - Parameter value: The bignum value to encode
  /// - Throws: A `Swift.Error` If any I/O error occurs
  ///
  private func encodeBignum(_ value: BigUInt) throws {

    // Get bytes magnitude (absolute value) in big-endian order
    let bytes = value.magnitude.encode()

    // Encode with appropriate tag
    try encodeTagged(tag: 2, value: .bytes(Data(bytes)))
  }

  /// Encodes a decimal fraction value.
  ///
  /// - Parameter value: The decimal fraction value to encode
  /// - Throws: A `Swift.Error` if any I/O error occurs
  ///
  private func encodeDecimalFraction(_ value: BigDecimal) throws {
    let exponent = value.exponent
    let mantissa = value.mantissa
    try encodeTagged(tag: CBORStructure.Tags.decimalFractionTag, value: [.number(exponent), .number(mantissa)])
  }

  // MARK: - Indefinite length items

  /// Encodes a CBOR value indicating the opening of an indefinite-length data item.
  ///
  /// The user is responsible encoding subsequent valid CBOR items.
  ///
  /// - Attention: The user must end the indefinite item encoding with the end
  /// indicator, which can be encoded with `encodeStreamEnd()`.
  ///
  /// - Parameter type: The type of indefinite-item to begin encoding.
  ///   - map: Indefinite map item (requires encoding zero or more "pairs" of items only)
  ///   - array: Indefinite array item
  ///   - string: Indefinite string item (requires encoding zero or more `string` items only)
  ///   - byteString: Indefinite string item (requires encoding zero or more `byte-string` items only)
  /// - Throws: A `Swift.Error` if any I/O error occurs
  ///
  private func encodeIndefiniteStart(for type: StreamableItemType) throws {
    try stream.writeByte(type.rawValue)
  }

  // Encodes the indefinite-item end indicator.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func encodeIndefiniteEnd() throws {
    try stream.writeByte(0xFF)
  }

  private func encodeStream(_ type: CBORWriter.StreamableItemType, block: (CBORWriter) throws -> Void) throws {
    try encodeIndefiniteStart(for: type)
    defer { try? encodeIndefiniteEnd() }
    try block(self)
  }

  private func deterministicBytes(of value: Value) throws -> Data {
    let out = CBORDataStream()
    try CBORWriter(stream: out, options: Options(deterministic: true)).encode(value)
    return out.data
  }

}

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


public struct CBORWriter: FormatWriter {

  public struct Options: Sendable {

    public static let `default` = Self()

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

    public func write(_ value: Value) throws {
      try writer.write(value)
    }

    public func write(_ values: some Sequence<Value>) throws {
      try writer.writeArrayChunk(values)
    }

    public consuming func end() throws {
      try writer.writeIndefiniteEnd()
    }
  }

  public struct MapStream: ~Copyable {
    private var writer: CBORWriter

    private init(writer: CBORWriter) {
      self.writer = writer
    }

    public func write(_ key: Value, _ value: Value) throws {
      try writer.write(key)
      try writer.write(value)
    }

    public func write(_ value: Value.Object) throws {
      try writer.writeMapChunk(value.elements)
    }

    public func write(_ values: some Sequence<(key: Value, value: Value)>) throws {
      try writer.writeMapChunk(values)
    }

    public func write(_ values: some Sequence<(Value, Value)>) throws {
      try writer.writeMapChunk(values.lazy.map { ($0, $1) })
    }

    public consuming func end() throws {
      try writer.writeIndefiniteEnd()
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

  /// Write a value into a new in-memory Data buffer.
  public static func write(_ value: Value, options: Options = .default) throws -> Data {
    let dataStream = CBORDataStream()
    let writer = CBORWriter(stream: dataStream, options: options)
    try writer.write(value)
    return dataStream.data
  }

  public init(stream: CBOROutputStream, options: Options = Options()) {
    self.stream = stream
    self.options = options
  }

  public var format: Format { CBOR.format }

  /// Write a single CBOR item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  public func write(_ value: Value) throws {
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
            try writeUInt64(UInt64(int64))
          } else {
            try writeNegativeInt(int64)
          }
        case .uint64(let uint64):
          try writeUInt64(uint64)

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

  public func write(_ value: Value, tag: UInt64) throws {
    try writeTagged(tag: tag, value: value)
  }

  /// Write any signed/unsigned integer, `or`ing `majorType` and
  /// `additional` data with first byte.
  private func writeLength(_ val: Int, majorType: UInt8) throws {
    try writeVarUInt(UInt64(val), modifier: (majorType << 5))
  }

  // MARK: - major 0: unsigned integer

  /// Write an 8bit unsigned integer, `or`ing `modifier` with first byte.
  private func writeUInt8(_ val: UInt8, modifier: UInt8 = 0) throws {
    if val < 24 {
      try stream.writeByte(val | modifier)
    } else {
      try stream.writeByte(0x18 | modifier)
      try stream.writeByte(val)
    }
  }

  /// Write a 16bit unsigned integer, `or`ing `modifier` with first byte.
  private func writeUInt16(_ val: UInt16, modifier: UInt8 = 0) throws {
    try stream.writeByte(0x19 | modifier)
    try stream.writeInt(val)
  }

  /// Write a 32bit unsigned integer, `or`ing `modifier` with first byte.
  private func writeUInt32(_ val: UInt32, modifier: UInt8 = 0) throws {
    try stream.writeByte(0x1A | modifier)
    try stream.writeInt(val)
  }

  /// Write a 64bit unsigned integer, `or`ing `modifier` with first byte.
  private func writeUInt64(_ val: UInt64, modifier: UInt8 = 0) throws {
    try stream.writeByte(0x1B | modifier)
    try stream.writeInt(val)
  }

  /// Write any unsigned integer, `or`ing `modifier` with first byte.
  private func writeVarUInt(_ val: UInt64, modifier: UInt8 = 0) throws {
    switch val {
    case let val where val <= UInt8.max: try writeUInt8(UInt8(val), modifier: modifier)
    case let val where val <= UInt16.max: try writeUInt16(UInt16(val), modifier: modifier)
    case let val where val <= UInt32.max: try writeUInt32(UInt32(val), modifier: modifier)
    default: try writeUInt64(val, modifier: modifier)
    }
  }

  // MARK: - major 1: negative integer

  /// Write any negative integer item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func writeNegativeInt(_ val: Int64) throws {
    try writeNegativeInt(val, modifier: 0)
  }

  private func writeNegativeInt(_ val: Int64, modifier: UInt8) throws {
    assert(val < 0)
    try writeVarUInt(~UInt64(bitPattern: val), modifier: 0b0010_0000 | modifier)
  }

  // MARK: - major 2: bytestring

  /// Write provided data as a byte string item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func writeByteString(_ str: Data) throws {
    try writeLength(str.count, majorType: 0b010)
    try stream.writeBytes(str)
  }

  // MARK: - major 3: UTF8 string

  /// Write provided data as a UTF-8 string item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
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

  /// Write an array of CBOR items.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func writeArray(_ array: Value.Array) throws {
    try writeLength(array.count, majorType: 0b100)
    try writeArrayChunk(array)
  }

  /// Write an array chunk of CBOR items.
  ///
  /// - Note: This is specifically for use when creating
  /// indefinite arrays; see `writeStreamStart` & `writeStreamEnd`.
  /// Any number of chunks can be written in an indefinite array.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func writeArrayChunk(_ chunk: some Sequence<Value>) throws {
    for item in chunk {
      try write(item)
    }
  }

  // MARK: - major 5: a map of pairs of data items

  /// Write a map of CBOR item pairs.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func writeMap(_ map: Value.Object) throws {
    try writeLength(map.count, majorType: 0b101)
    if options.deterministic {
      try map.map { (try deterministicBytes(of: $0), ($0, $1)) }
        .sorted { (itemA, itemB) in itemA.0.lexicographicallyPrecedes(itemB.0) }
        .map { $1 }
        .forEach { key, value in
          try write(key)
          try write(value)
        }
    } else {
      try writeMapChunk(map)
    }
  }

  /// Write a map chunk of CBOR item pairs.
  ///
  /// - Note: This is specifically for use when creating
  /// indefinite maps; see `writeStreamStart` & `writeStreamEnd`.
  /// Any number of chunks can be written in an indefinite map.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func writeMapChunk(_ map: some Sequence<(key: Value, value: Value)>) throws {
    for (key, value) in map {
      try write(key)
      try write(value)
    }
  }

  // MARK: - major 6: tagged values

  /// Write a tagged CBOR item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func writeTagged(tag: UInt64, value: Value) throws {
    try writeVarUInt(tag, modifier: 0b1100_0000)
    try write(value)
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

  /// Write CBOR null item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func writeNull() throws {
    try stream.writeByte(0xF6)
  }

  /// Write CBOR undefined item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func writeUndefined() throws {
    try stream.writeByte(0xF7)
  }

  /// Write Half item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func writeHalf(_ val: Float16) throws {
    try stream.writeByte(0xF9)
    try stream.writeInt(val.bitPattern)
  }

  /// Write Float item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
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
    try stream.writeInt(val.bitPattern)
  }

  /// Write Double item.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
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
    try stream.writeInt(val.bitPattern)
  }

  /// Write Bool item.
  ///
  /// - Throws: A `Swift.Error`: If any I/O error occurs
  ///
  private func writeBool(_ val: Bool) throws {
    try stream.writeByte(val ? 0xF5 : 0xF4)
  }

  /// Write a bignum value.
  ///
  /// - Parameter value: The bignum value to encode
  /// - Throws: A `Swift.Error` If any I/O error occurs
  ///
  private func writeBignum(_ value: BigInt) throws {

    // Get bytes magnitude (absolute value) in big-endian order
    let bytes = value.magnitude.encode()

    // Encode with appropriate tag
    try writeTagged(tag: value.isNegative ? 3 : 2, value: .bytes(Data(bytes)))
  }

  /// Write a bignum value.
  ///
  /// - Parameter value: The bignum value to write
  /// - Throws: A `Swift.Error` If any I/O error occurs
  ///
  private func writeBignum(_ value: BigUInt) throws {

    // Get bytes magnitude in big-endian order
    let bytes = value.encode()

    // Write with appropriate tag
    try writeTagged(tag: 2, value: .bytes(Data(bytes)))
  }

  /// Write a decimal fraction value.
  ///
  /// - Parameter value: The decimal fraction value to write
  /// - Throws: A `Swift.Error` if any I/O error occurs
  ///
  private func writeDecimalFraction(_ value: BigDecimal) throws {
    let exponent = value.exponent
    let mantissa = value.mantissa
    try writeTagged(tag: CBORStructure.Tags.decimalFractionTag, value: [.number(exponent), .number(mantissa)])
  }

  // MARK: - Indefinite length items

  /// Write a CBOR value indicating the opening of an indefinite-length data item.
  ///
  /// The user is responsible encoding subsequent valid CBOR items.
  ///
  /// - Attention: The user must end the indefinite item encoding with the end
  /// indicator, which can be written with `writeStreamEnd()`.
  ///
  /// - Parameter type: The type of indefinite-item to begin encoding.
  ///   - map: Indefinite map item (requires encoding zero or more "pairs" of items only)
  ///   - array: Indefinite array item
  ///   - string: Indefinite string item (requires encoding zero or more `string` items only)
  ///   - byteString: Indefinite string item (requires encoding zero or more `byte-string` items only)
  /// - Throws: A `Swift.Error` if any I/O error occurs
  ///
  private func writeIndefiniteStart(for type: StreamableItemType) throws {
    try stream.writeByte(type.rawValue)
  }

  /// Write the indefinite-item end indicator.
  ///
  /// - Throws:
  ///     - `Swift.Error`: If any I/O error occurs
  private func writeIndefiniteEnd() throws {
    try stream.writeByte(0xFF)
  }

  private func writeStream(_ type: CBORWriter.StreamableItemType, block: (CBORWriter) throws -> Void) throws {
    try writeIndefiniteStart(for: type)
    defer { try? writeIndefiniteEnd() }
    try block(self)
  }

  private func deterministicBytes(of value: Value) throws -> Data {
    let out = CBORDataStream()
    try CBORWriter(stream: out, options: Options(deterministic: true)).write(value)
    return out.data
  }

}

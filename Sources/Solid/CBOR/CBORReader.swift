//
//  CBORReader.swift
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


public struct CBORReader: FormatReader {

  public typealias Error = CBOR.Error

  public struct Options {

    public enum Undefined {
      case throwError
      case convertToNull
    }

    public var undefined: Undefined

    public init(undefined: Undefined = .throwError) {
      self.undefined = undefined
    }
  }

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
        // mask only allows values from 0-3
        throw Error.invalidIntegerSize
      }
    }
  }

  private let stream: CBORInputStream
  private let options: Options

  public init(stream: CBORInputStream, options: Options = Options()) {
    self.stream = stream
    self.options = options
  }

  public init(data: Data, options: Options = Options()) {
    self.init(stream: CBORDataStream(data: data), options: options)
  }

  public var format: Format { CBOR.format }

  public func read() throws -> Value {
    try decodeRequiredItem()
  }

  private func readHalf() throws -> Float16 {
    return Float16(bitPattern: try stream.readInt(UInt16.self))
  }

  private func readFloat() throws -> Float32 {
    return Float32(bitPattern: try stream.readInt(UInt32.self))
  }

  private func readDouble() throws -> Float64 {
    return Float64(bitPattern: try stream.readInt(UInt64.self))
  }

  private func readVarUInt(_ initByte: UInt8, base: UInt8) throws -> UInt64 {
    guard initByte > base + 0x17 else { return UInt64(initByte - base) }

    switch try VarUIntSize.from(serialized: initByte) {
    case .uint8: return UInt64(try stream.readInt(UInt8.self))
    case .uint16: return UInt64(try stream.readInt(UInt16.self))
    case .uint32: return UInt64(try stream.readInt(UInt32.self))
    case .uint64: return UInt64(try stream.readInt(UInt64.self))
    }
  }

  private func readLength(_ initByte: UInt8, base: UInt8) throws -> Int {
    let length = try readVarUInt(initByte, base: base)

    guard length <= Int.max else {
      throw Error.sequenceTooLong
    }

    return Int(length)
  }

  /// Decodes `count` CBOR items.
  ///
  /// - Returns: An array of the decoded items
  /// - Throws:
  ///     - `CBORSerialization.Error`: If corrupted data is encountered,
  ///     including ``CBORSerialization/Error/invalidBreak`` if a break indicator is encountered in
  ///     an item slot
  ///     - `Swift.Error`: If any I/O error occurs
  private func decodeItems(count: Int) throws -> Value.Array {
    var result: Value.Array = []
    for _ in 0..<count {
      let item = try decodeRequiredItem()
      result.append(item)
    }
    return result
  }

  /// Decodes CBOR items until an indefinite-element break indicator
  /// is encountered.
  ///
  /// - Returns: An array of the decoded items
  /// - Throws:
  ///     - `CBORSerialization.Error`: If corrupted data is encountered
  ///     - `Swift.Error`: If any I/O error occurs
  private func decodeItemsUntilBreak() throws -> Value.Array {
    var result: Value.Array = []
    while let item = try decodeItem() {
      result.append(item)
    }
    return result
  }

  /// Decodes `count` key-value pairs of CBOR items.
  ///
  /// - Returns: A map of the decoded key-value pairs
  /// - Throws:
  ///     - `CBORSerialization.Error`: If corrupted data is encountered,
  ///     including ``CBORSerialization/Error/invalidBreak`` if a break indicator is encountered in
  ///     the either the key or value slot
  ///     - `Swift.Error`: If any I/O error occurs
  private func decodeItemPairs(count: Int) throws -> Value.Object {
    var result: Value.Object = [:]
    for _ in 0..<count {
      let key = try decodeRequiredItem()
      let val = try decodeRequiredItem()
      result[key] = val
    }
    return result
  }

  /// Decodes key-value pairs of CBOR items until an indefinite-element
  /// break indicator is encontered.
  ///
  /// - Returns: A map of the decoded key-value pairs
  /// - Throws:
  ///     - `CBORSerialization.Error`: If corrupted data is encountered,
  ///     including ``CBORSerialization/Error/invalidBreak`` if a break indicator is encountered in
  ///     the value slot
  ///     - `Swift.Error`: If any I/O error occurs
  private func decodeItemPairsUntilBreak() throws -> Value.Object {
    var result: Value.Object = [:]
    while let key = try decodeItem() {
      let val = try decodeRequiredItem()
      result[key] = val
    }
    return result
  }

  /// Decodes any CBOR item that is not an indefinite-element break indicator.
  ///
  /// - Returns: A non-break CBOR item
  /// - Throws:
  ///     - `CBORSerialization.Error`: If corrupted data is encountered,
  ///     including ``CBORSerialization/Error/invalidBreak`` if an indefinite-element indicator is
  ///     encountered
  ///     - `Swift.Error`: If any I/O error occurs
  func decodeRequiredItem() throws -> Value {
    guard let item = try decodeItem() else { throw Error.invalidBreak }
    return item
  }

  /// Decodes any CBOR item.
  ///
  /// - Returns: A CBOR item or nil if an indefinite-element break indicator.
  /// - Throws:
  ///     - `CBORSerialization.Error`: If corrupted data is encountered
  ///     - `Swift.Error`: If any I/O error occurs
  private func decodeItem() throws -> Value? {
    let initByte = try stream.readByte()

    switch initByte {
    // positive integers
    case 0x00...0x1B:
      return .number(try readVarUInt(initByte, base: 0x00))

    // negative integers
    case 0x20...0x3B:
      return .number(try readVarUInt(initByte, base: 0x20))

    // byte strings
    case 0x40...0x5B:
      let numBytes = try readLength(initByte, base: 0x40)
      return .bytes(try stream.readBytes(count: numBytes))
    case 0x5F:
      return .bytes(try readIndefiniteByteString())

    // utf-8 strings
    case 0x60...0x7B:
      return .string(try readFiniteString(initByte: initByte))
    case 0x7F:
      return .string(try readIndefiniteString())

    // arrays
    case 0x80...0x9B:
      let itemCount = try readLength(initByte, base: 0x80)
      return .array(try decodeItems(count: itemCount))
    case 0x9F:
      return .array(try decodeItemsUntilBreak())

    // pairs
    case 0xA0...0xBB:
      let itemPairCount = try readLength(initByte, base: 0xA0)
      return .object(try decodeItemPairs(count: itemPairCount))
    case 0xBF:
      return .object(try decodeItemPairsUntilBreak())

    // tagged values
    case 0xC0...0xDB:
      let tag = try readVarUInt(initByte, base: 0xC0)
      switch tag {
      case CBORStructure.Tags.positiveBignum: return try decodeBigInt(isNegative: false)
      case CBORStructure.Tags.negativeBignum: return try decodeBigInt(isNegative: true)
      case CBORStructure.Tags.decimalFractionTag: return try decodeBigNumber(base: Self.decimalFractionRadix)
      case CBORStructure.Tags.bigFloatTag: return try decodeBigNumber(base: Self.bigFloatRadix)
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
        throw Error.undefinedItem
      case .convertToNull:
        return .null
      }

    case 0xF8:
      return .number(try stream.readByte())

    case 0xF9:
      return .number(try readHalf())
    case 0xFA:
      return .number(try readFloat())
    case 0xFB:
      return .number(try readDouble())

    case 0xFF:
      return nil

    default:
      throw Error.invalidItemType
    }
  }

  private static let decimalFractionRadix: BigDecimal = .ten
  private static let bigFloatRadix: BigDecimal = 2

  private func decodeBigInt(isNegative: Bool) throws -> Value {
    let item = try decodeRequiredItem()
    guard case .bytes(let bytes) = item, !bytes.isEmpty else {
      throw Error.invalidItemType
    }
    return .number(BigInt(isNegative: isNegative, magnitude: BigUInt(encoded: bytes)))
  }

  private func decodeBigNumber(base: BigDecimal) throws -> Value {
    let item = try decodeRequiredItem()
    guard
      case .array(let items) = item, items.count == 2,
      case .number(let exponentNum) = items[0],
      case .number(let mantissaNum) = items[1]
    else {
      throw Error.invalidItemType
    }
    guard let exponent = Int(exactly: exponentNum.decimal) else {
      throw Error.unsupportedValue
    }
    let decimal = mantissaNum.decimal * base.raised(to: exponent)
    return .number(decimal)
  }

  private func readFiniteString(initByte: UInt8) throws -> String {
    let numBytes = try readLength(initByte, base: 0x60)
    guard let string = String(data: try stream.readBytes(count: numBytes), encoding: .utf8) else {
      throw Error.invalidUTF8String
    }
    return string
  }

  private func readIndefiniteString() throws -> String {
    return try decodeItemsUntilBreak()
      .map { item -> String in
        guard case .string(let string) = item else { throw Error.invalidIndefiniteElement }
        return string
      }
      .joined(separator: "")
  }

  private func readIndefiniteByteString() throws -> Data {
    let datas = try decodeItemsUntilBreak()
      .map { cbor -> Data in
        guard case .bytes(let bytes) = cbor else { throw Error.invalidIndefiniteElement }
        return bytes
      }
      .joined()
    return Data(datas)
  }

}

//
//  CBORDeterministicKeyEncoder.swift
//  SolidFoundation
//
//  Created by Codex on 5/9/26.
//

import Foundation
import SolidData

enum CBORDeterministicKeyEncoder {

  static func encode(_ value: Value) throws -> Data {
    if let fast = try fastEncode(value) {
      return fast
    }
    return try CBOREncoder.encodeValue(value, deterministic: true)
  }

  private static func fastEncode(_ value: Value) throws -> Data? {
    switch value {
    case .null:
      var data = Data()
      data.reserveCapacity(1)
      data.append(0xF6)
      return data

    case .bool(let bool):
      var data = Data()
      data.reserveCapacity(1)
      data.append(bool ? 0xF5 : 0xF4)
      return data

    case .string(let string):
      var data = Data()
      data.reserveCapacity(lengthHeaderSize(for: string.utf8.count) + string.utf8.count)
      appendLength(string.utf8.count, majorType: 0b011, into: &data)
      data.append(contentsOf: string.utf8)
      return data

    case .bytes(let bytes):
      var data = Data()
      data.reserveCapacity(lengthHeaderSize(for: bytes.count) + bytes.count)
      appendLength(bytes.count, majorType: 0b010, into: &data)
      data.append(bytes)
      return data

    case .number(let number):
      if let int64: Int64 = number.int(as: Int64.self) {
        var data = Data()
        data.reserveCapacity(9)
        if int64 >= 0 {
          appendIntHeader(majorOffset: 0x00, value: UInt64(int64), into: &data)
        } else {
          appendIntHeader(majorOffset: 0x20, value: UInt64(bitPattern: ~int64), into: &data)
        }
        return data
      }
      if let uint64: UInt64 = number.int(as: UInt64.self) {
        var data = Data()
        data.reserveCapacity(9)
        appendIntHeader(majorOffset: 0x00, value: uint64, into: &data)
        return data
      }
      return nil

    default:
      return nil
    }
  }

  private static func lengthHeaderSize(for length: Int) -> Int {
    let value = UInt64(length)
    if value < 24 { return 1 }
    if value <= UInt8.max { return 2 }
    if value <= UInt16.max { return 3 }
    if value <= UInt32.max { return 5 }
    return 9
  }

  private static func appendLength(_ length: Int, majorType: UInt8, into data: inout Data) {
    appendIntHeader(majorOffset: majorType << 5, value: UInt64(length), into: &data)
  }

  private static func appendIntHeader(majorOffset: UInt8, value: UInt64, into data: inout Data) {
    if value < 24 {
      data.append(majorOffset | UInt8(value))
    } else if value <= UInt8.max {
      data.append(majorOffset | 0x18)
      data.append(UInt8(value))
    } else if value <= UInt16.max {
      data.append(majorOffset | 0x19)
      var int = UInt16(value).bigEndian
      withUnsafeBytes(of: &int) { data.append(contentsOf: $0) }
    } else if value <= UInt32.max {
      data.append(majorOffset | 0x1A)
      var int = UInt32(value).bigEndian
      withUnsafeBytes(of: &int) { data.append(contentsOf: $0) }
    } else {
      data.append(majorOffset | 0x1B)
      var int = value.bigEndian
      withUnsafeBytes(of: &int) { data.append(contentsOf: $0) }
    }
  }
}

//
//  CBORValueWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/18/26.
//

import Foundation
import SolidData

/// Synchronous CBOR writer that renders ``Value`` instances.
public final class CBORValueWriter: FormatWriter {

  public struct Options: Sendable {

    public static let `default` = Self()

    public var deterministic: Bool
    public var includeContainerSizes: Bool

    public init(deterministic: Bool = false, includeContainerSizes: Bool = true) {
      self.deterministic = deterministic
      self.includeContainerSizes = includeContainerSizes
    }
  }

  private let options: Options
  private var output = Data()

  /// Write a value into a new in-memory `Data` buffer.
  public static func write(_ value: Value, options: Options = .default) throws -> Data {
    let writer = CBORValueWriter(options: options)
    try writer.write(value)
    return writer.data()
  }

  public init(options: Options = .default) {
    self.options = options
  }

  public var format: Format { CBOR.format }

  public func write(_ value: Value) throws {
    let encoder = CBORValueEventEncoder(
      deterministic: options.deterministic,
      includeContainerSizes: options.includeContainerSizes
    )
    let events = try encoder.encode(value)
    let streamEncoder = CBOREncoder(options: .init(deterministic: options.deterministic, deterministicMode: .none))
    var buffer = FormatStreamEncoderBuffer(encoder: streamEncoder)
    output = try buffer.encode(events: events)
  }

  /// Rendered CBOR bytes.
  public func data() -> Data {
    output
  }
}

private struct CBORValueEventEncoder {
  let deterministic: Bool
  let includeContainerSizes: Bool

  func encode(_ value: Value) throws -> [ValueEvent] {
    var events: [ValueEvent] = []
    try encode(value, into: &events)
    return events
  }

  func encode(_ value: Value, into events: inout [ValueEvent]) throws {
    switch value {
    case .tagged(let tag, let inner):
      events.append(.tag(tag))
      try encode(inner, into: &events)

    case .array(let array):
      events.append(.beginArray(count: includeContainerSizes ? array.count : nil))
      for item in array {
        try encode(item, into: &events)
      }
      events.append(.endArray)

    case .object(let object):
      events.append(.beginObject(count: includeContainerSizes ? object.count : nil))
      if deterministic {
        let entries = try object.map { key, value in
          (try deterministicBytes(of: key), key, value)
        }
        for (_, key, value) in entries.sorted(by: { $0.0.lexicographicallyPrecedes($1.0) }) {
          events.append(.key(key))
          try encode(value, into: &events)
        }
      } else {
        for (key, value) in object {
          events.append(.key(key))
          try encode(value, into: &events)
        }
      }
      events.append(.endObject)

    default:
      events.append(.scalar(value))
    }
  }

  private func deterministicBytes(of value: Value) throws -> Data {
    if let fast = try fastDeterministicBytes(of: value) {
      return fast
    }
    return try CBOREncoder.encodeValue(value, deterministic: true)
  }

  private func fastDeterministicBytes(of value: Value) throws -> Data? {
    switch value {
    case .null:
      return Data([0xF6])
    case .bool(let bool):
      return Data([bool ? 0xF5 : 0xF4])
    case .string(let string):
      return encodedTextString(string)
    case .bytes(let bytes):
      return encodedByteString(bytes)
    case .number(let number):
      if let int64: Int64 = number.int(as: Int64.self) {
        if int64 >= 0 {
          return encodedUnsigned(UInt64(int64))
        }
        let magnitude = UInt64(bitPattern: ~int64)
        return encodedNegative(magnitude)
      }
      if let uint64: UInt64 = number.int(as: UInt64.self) {
        return encodedUnsigned(uint64)
      }
      return nil
    default:
      return nil
    }
  }

  private func encodedUnsigned(_ value: UInt64) -> Data {
    var data = Data()
    if value < 24 {
      data.append(UInt8(value))
    } else if value <= UInt8.max {
      data.append(0x18)
      data.append(UInt8(value))
    } else if value <= UInt16.max {
      data.append(0x19)
      var int = UInt16(value).bigEndian
      withUnsafeBytes(of: &int) { data.append(contentsOf: $0) }
    } else if value <= UInt32.max {
      data.append(0x1A)
      var int = UInt32(value).bigEndian
      withUnsafeBytes(of: &int) { data.append(contentsOf: $0) }
    } else {
      data.append(0x1B)
      var int = UInt64(value).bigEndian
      withUnsafeBytes(of: &int) { data.append(contentsOf: $0) }
    }
    return data
  }

  private func encodedNegative(_ magnitude: UInt64) -> Data {
    var data = Data()
    if magnitude < 24 {
      data.append(0x20 | UInt8(magnitude))
    } else if magnitude <= UInt8.max {
      data.append(0x38)
      data.append(UInt8(magnitude))
    } else if magnitude <= UInt16.max {
      data.append(0x39)
      var int = UInt16(magnitude).bigEndian
      withUnsafeBytes(of: &int) { data.append(contentsOf: $0) }
    } else if magnitude <= UInt32.max {
      data.append(0x3A)
      var int = UInt32(magnitude).bigEndian
      withUnsafeBytes(of: &int) { data.append(contentsOf: $0) }
    } else {
      data.append(0x3B)
      var int = UInt64(magnitude).bigEndian
      withUnsafeBytes(of: &int) { data.append(contentsOf: $0) }
    }
    return data
  }

  private func encodedByteString(_ bytes: Data) -> Data {
    var data = Data()
    appendLength(bytes.count, majorType: 0b010, into: &data)
    data.append(bytes)
    return data
  }

  private func encodedTextString(_ string: String) -> Data {
    var data = Data()
    let utf8 = Data(string.utf8)
    appendLength(utf8.count, majorType: 0b011, into: &data)
    data.append(utf8)
    return data
  }

  private func appendLength(_ length: Int, majorType: UInt8, into data: inout Data) {
    let value = UInt64(length)
    let modifier = UInt8(majorType << 5)
    if value < 24 {
      data.append(UInt8(value) | modifier)
    } else if value <= UInt8.max {
      data.append(0x18 | modifier)
      data.append(UInt8(value))
    } else if value <= UInt16.max {
      data.append(0x19 | modifier)
      var int = UInt16(value).bigEndian
      withUnsafeBytes(of: &int) { data.append(contentsOf: $0) }
    } else if value <= UInt32.max {
      data.append(0x1A | modifier)
      var int = UInt32(value).bigEndian
      withUnsafeBytes(of: &int) { data.append(contentsOf: $0) }
    } else {
      data.append(0x1B | modifier)
      var int = UInt64(value).bigEndian
      withUnsafeBytes(of: &int) { data.append(contentsOf: $0) }
    }
  }
}

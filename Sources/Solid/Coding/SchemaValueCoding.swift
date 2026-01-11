//
//  SchemaValueCoding.swift
//  SolidFoundation
//
//  Created by Warp on 12/24/25.
//

import Foundation
import SolidData
import SolidNumeric
import SolidSchema
import SolidTempo

public enum SchemaCodingError: Swift.Error, Sendable {
  case validationFailed
  case missingValue(Pointer)
  case typeMismatch(expected: String, at: Pointer, actual: Value)
  case numericRangeMismatch(expected: Any.Type, at: Pointer, actual: Value)
  case contentDecodingFailed(encoding: String, at: Pointer)
  case contentEncodingFailed(encoding: String, at: Pointer, error: any Error)
  case unsupportedEncoding(type: ValueType, for: Any.Type)
  case invalidSchema(for: Schema, at: Pointer)
  case invalidValue(for: Schema, at: Pointer, actual: Value)
}

// MARK: - Decoder

public struct SchemaValueDecoder: SchemaDecoder {

  private let root: Value
  private var base: Pointer
  private let annotations: [Pointer: [Schema.Annotation]]
  private let options: Schema.Options

  public init(
    schema: Schema,
    value: Value,
    options: Schema.Options = .default
  ) throws {
    let decodeOptions = options.collectAnnotations(.all)
    let (result, anns) = try Schema.Validator.validate(
      instance: value,
      using: schema,
      outputFormat: .verbose,
      options: decodeOptions
    )
    guard result.isValid else {
      throw SchemaCodingError.validationFailed
    }
    self.init(
      root: value,
      base: .root,
      annotations: Dictionary(grouping: anns, by: \.instanceLocation),
      options: decodeOptions
    )
  }

  public init(
    root: Value,
    base: Pointer,
    annotations: [Pointer: [Schema.Annotation]],
    options: Schema.Options = .default
  ) {
    self.root = root
    self.base = base
    self.annotations = annotations
    self.options = options
  }

  func value(at pointer: Pointer) throws -> Value {
    guard let value = root[pointer] else {
      throw SchemaCodingError.missingValue(base / pointer)
    }
    return value
  }

  func value<R>(at pointer: Pointer, as type: String, by extract: (Value) -> R?) throws -> R {
    let abs = base / pointer
    guard let value = root[pointer] else {
      throw SchemaCodingError.missingValue(abs)
    }
    guard let result = extract(value) else {
      throw SchemaCodingError.typeMismatch(expected: type, at: abs, actual: value)
    }
    return result
  }

  // MARK: - Annotation helpers

  private func annotation(for keyword: Schema.Keyword, at pointer: Pointer) -> Schema.Annotation? {
    let abs = base / pointer
    return annotations[abs]?.first { $0.keyword == keyword }
  }

  private func contentEncoding(at pointer: Pointer) -> String? {
    annotation(for: .contentEncoding, at: pointer)?.value.string
  }

  private func format(at pointer: Pointer) -> String? {
    annotation(for: .format, at: pointer)?.value.string
  }

  private func bitWidth(at pointer: Pointer) -> Schema.SolidCoding.BitWidth.Size? {
    guard let annVal = annotation(for: .bitWidth, at: pointer)?.value else { return nil }
    return .init(value: annVal)
  }

  private func units(at pointer: Pointer) -> String? {
    annotation(for: .units, at: pointer)?.value.string
  }

  private func convertedFormatValue(at pointer: Pointer) -> Value? {
    guard
      let ann = annotation(for: .format, at: pointer),
      case .object(let obj) = ann.value,
      let result = obj[.string("result")]
    else { return nil }
    return result
  }

  // Primitive decodes

  public mutating func decode(_ type: Bool.Type, at pointer: Pointer) throws -> Bool {
    return try value(at: pointer, as: "bool") { $0.bool }
  }

  public mutating func decode<I: FixedWidthInteger>(
    _ requestedType: I.Type = I.self,
    at pointer: Pointer,
  ) throws -> I {
    let number = try value(at: pointer, as: "number") { $0.number }
    guard let int = number.int(as: I.self) else {
      throw SchemaCodingError.numericRangeMismatch(expected: I.self, at: base / pointer, actual: .number(number))
    }
    return int
  }

  public mutating func decode(
    _ requestedType: BigInt.Type = BigInt.self,
    at pointer: Pointer,
  ) throws -> BigInt {
    let number = try value(at: pointer, as: "number") { $0.number }
    guard let int = number.integer else {
      throw SchemaCodingError.numericRangeMismatch(expected: BigInt.self, at: base / pointer, actual: .number(number))
    }
    return int
  }

  public mutating func decode(
    _ requestedType: BigUInt.Type = BigUInt.self,
    at pointer: Pointer,
  ) throws -> BigUInt {
    let number = try value(at: pointer, as: "number") { $0.number }
    guard let int = number.integer, let uint = BigUInt(exactly: int) else {
      throw SchemaCodingError.numericRangeMismatch(expected: BigInt.self, at: base / pointer, actual: .number(number))
    }
    return uint
  }

  public mutating func decode<F: BinaryFloatingPoint>(
    _ requestedType: F.Type = F.self,
    at pointer: Pointer,
  ) throws -> F {
    let number = try value(at: pointer, as: "number") { $0.number }
    guard let float = number.float(as: F.self) else {
      throw SchemaCodingError.numericRangeMismatch(expected: BigInt.self, at: base / pointer, actual: .number(number))
    }
    return float
  }

  public mutating func decode(_ type: String.Type, at pointer: Pointer) throws -> String {
    return try value(at: pointer, as: "string") { $0.string }
  }

  public mutating func decode(_ type: Data.Type, at pointer: Pointer) throws -> Data {
    let absPointer = base / pointer
    let value = try value(at: pointer)
    switch value {

    case .bytes(let data):
      return data

    case .string(let string):
      let encoding = contentEncoding(at: absPointer) ?? "base64"
      let codec = try options.contentEncodingLocator.locate(contentEncoding: encoding)
      guard case .bytes(let data) = try codec.decode(string) else {
        throw SchemaCodingError.contentDecodingFailed(encoding: encoding, at: absPointer)
      }
      return data

    default:
      throw SchemaCodingError.typeMismatch(expected: "bytes or string", at: absPointer, actual: value)
    }
  }

  public mutating func decode<T>(_ type: T.Type, at pointer: Pointer) throws -> T where T: SchemaDecodable {
    try subDecode(at: pointer) { decoder in
      return try T(from: &decoder)
    }
  }

  public mutating func decode<T>(
    _ requestedType: T.Type,
    at pointer: Pointer,
    using schema: Schema
  ) throws -> T where T: ExplicitSchemaDecodable {
    try subDecode(at: pointer) { decoder in
      return try T(from: &decoder, using: schema)
    }
  }

  public mutating func decode<T>(
    _ requestedType: T.Type,
    at pointer: Pointer,
    nestedIn schema: Schema
  ) throws -> T where T: ExplicitSchemaDecodable {
    try subDecode(at: pointer) { decoder in
      return try T(from: &decoder, using: schema)
    }
  }

  public mutating func decode(_ type: Value.Type, at pointer: Pointer) throws -> Value {
    let absPointer = base / pointer
    guard let value = root[absPointer] else {
      throw SchemaCodingError.missingValue(absPointer)
    }
    return value
  }

  public mutating func subDecode<R>(
    at pointer: Pointer,
    _ body: (inout any SchemaDecoder) throws -> R
  ) throws -> R {
    let child = try value(at: pointer)
    var decoder: any SchemaDecoder =
      SchemaValueDecoder(
        root: child,
        base: base / pointer,
        annotations: annotations,
        options: options
      )
    return try body(&decoder)
  }
}

// MARK: - Encoder

public struct SchemaValueEncoder: SchemaEncoder {

  public struct Options: Sendable {
    public var contentEncodingLocator: ContentEncodingLocator
    public var dateTimeEncoding: DateTimeEncoding = .iso8601String

    public enum DateTimeEncoding: Sendable {
      case iso8601String
      case millisecondsSinceEpoch
    }

    public init(
      contentEncodingLocation: ContentEncodingLocator,
      dateTimeEncoding: DateTimeEncoding = .iso8601String,
    ) {
      self.contentEncodingLocator = contentEncodingLocation
      self.dateTimeEncoding = dateTimeEncoding
    }
  }

  public private(set) var writer: any FormatWriter
  private let base: Pointer
  private let annotations: [Pointer: [Schema.Annotation]]
  private let options: Options

  public init(
    writer: any FormatWriter,
    base: Pointer = .root,
    annotations: [Pointer: [Schema.Annotation]] = [:],
    options: Options
  ) {
    self.writer = writer
    self.base = base
    self.annotations = annotations
    self.options = options
  }

  public func resolveType(
    for schema: Schema,
    defaults: (text: Schema.InstanceType, binary: Schema.InstanceType)
  ) -> Schema.InstanceType {
    switch writer.format.kind {
    case .binary: defaults.binary
    case .text: defaults.text
    }
  }

  private func annotation(for keyword: Schema.Keyword, at pointer: Pointer) -> Schema.Annotation? {
    annotations[base / pointer]?.first { $0.keyword == keyword }
  }

  public mutating func encode(_ bool: Bool, at pointer: Pointer) throws {
    try self.writer.write(.bool(bool))
  }

  public mutating func encode<I>(_ int: I, at pointer: Pointer) throws where I: FixedWidthInteger {
    let value: Value =
      switch int {
      case let i as Int: .number(i)
      case let i as UInt: .number(i)
      case let i as Int8: .number(i)
      case let i as UInt8: .number(i)
      case let i as Int16: .number(i)
      case let i as UInt16: .number(i)
      case let i as Int32: .number(i)
      case let i as UInt32: .number(i)
      case let i as Int64: .number(i)
      case let i as UInt64: .number(i)
      case let i as Int128: .number(i)
      case let i as UInt128: .number(i)
      default: fatalError("Unhandled integer type: \(I.self)")
      }
    try self.writer.write(value)
  }

  public mutating func encode(_ int: BigInt, at pointer: Pointer) throws {
    try self.writer.write(.number(int))
  }

  public mutating func encode(_ uint: BigUInt, at pointer: Pointer) throws {
    try self.writer.write(.number(uint))
  }

  public mutating func encode<F>(_ float: F, at pointer: Pointer) throws where F: BinaryFloatingPoint {
    let value: Value =
      switch float {
      case let f as Float16: .number(f)
      case let f as Float32: .number(f)
      case let f as Float64: .number(f)
      case let f as Double: .number(f)
      default: fatalError("Unhandled floating point type: \(F.self)")
      }
    try self.writer.write(value)
  }

  public mutating func encode(_ string: String, at pointer: Pointer) throws {
    try self.writer.write(.string(string))
  }

  public mutating func encode(_ data: Data, at pointer: Pointer) throws {
    let absPointer = base / pointer
    let value: Value
    if let encoding = annotation(for: .contentEncoding, at: absPointer)?.value.string {
      let encodedString: String
      do {
        let codec = try options.contentEncodingLocator.locate(contentEncoding: encoding)
        encodedString = try codec.encode(.bytes(data))
        value = .string(encodedString)
      } catch let e {
        throw SchemaCodingError.contentEncodingFailed(encoding: encoding, at: absPointer, error: e)
      }
    } else {
      value = .bytes(data)
    }
    try self.writer.write(value)
  }

  public mutating func encode<T>(_ value: T, at pointer: Pointer) throws where T: SchemaEncodable {
    try subEncode(at: pointer) { encoder in
      try value.encode(to: &encoder)
    }
  }

  public mutating func encode<T>(
    _ value: T,
    at pointer: Pointer,
    using schema: Schema
  ) throws where T: ExplicitSchemaEncodable {
    try subEncode(at: pointer) { encoder in
      try value.encode(to: &encoder, using: schema)
    }
  }

  public mutating func encode<T>(
    _ value: T,
    at pointer: Pointer,
    nestedIn schema: Schema
  ) throws where T: ExplicitSchemaEncodable {
    guard let nestedSchema = schema.locate(pointer) else {
      throw SchemaCodingError.invalidSchema(for: schema, at: pointer)
    }
    try encode(value, at: pointer, using: nestedSchema)
  }

  public mutating func encode(_ value: Value, at pointer: Pointer) throws {
    try self.writer.write(value)
  }

  public mutating func subEncode(at pointer: Pointer, _ body: (inout any SchemaEncoder) throws -> Void) throws {
    let absPointer = base / pointer
    var encoder: any SchemaEncoder =
      SchemaValueEncoder(
        writer: writer,
        base: absPointer,
        annotations: annotations,
        options: options
      )
    try body(&encoder)
  }
}

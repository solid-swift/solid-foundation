//
//  SchemaCodable.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/24/25.
//

import Foundation
import SolidData
import SolidNumeric
import SolidSchema
import SolidTempo


public protocol ExplicitSchemaEncodable {

  func encode(to encoder: inout some SchemaEncoder, using schema: Schema) throws

}


public protocol ExplicitSchemaDecodable {

  init(from decoder: inout some SchemaDecoder, using schema: Schema) throws

}


public protocol ExplicitSchemaCodable: ExplicitSchemaEncodable, ExplicitSchemaDecodable {}


public protocol SchemaEncodable {

  static var schema: Schema { get }

  func encode(to encoder: inout some SchemaEncoder) throws

}


extension SchemaEncodable where Self: ExplicitSchemaEncodable {

  public func encode(to encoder: inout some SchemaEncoder) throws {
    try encode(to: &encoder, using: Self.schema)
  }

}


public protocol SchemaDecodable {

  static var schema: Schema { get }

  init(from decoder: inout some SchemaDecoder) throws

}


extension SchemaDecodable where Self: ExplicitSchemaDecodable {

  public init(from decoder: inout some SchemaDecoder) throws {
    try self.init(from: &decoder, using: Self.schema)
  }

}


public protocol SchemaCodable: SchemaEncodable, SchemaDecodable {}


public protocol SchemaEncoder {

  func resolveType(
    for schema: Schema,
    defaults: (
      text: Schema.InstanceType,
      binary: Schema.InstanceType
    )
  ) -> Schema.InstanceType

  mutating func encode(_ value: Bool, at pointer: Pointer) throws
  mutating func encode<I: FixedWidthInteger>(_ value: I, at pointer: Pointer) throws
  mutating func encode(_ value: BigInt, at pointer: Pointer) throws
  mutating func encode(_ value: BigUInt, at pointer: Pointer) throws
  mutating func encode<F: BinaryFloatingPoint>(_ value: F, at pointer: Pointer) throws
  mutating func encode(_ value: String, at pointer: Pointer) throws
  mutating func encode(_ value: Data, at pointer: Pointer) throws

  mutating func encode<T: SchemaEncodable>(_ value: T, at pointer: Pointer) throws
  mutating func encode<T: ExplicitSchemaEncodable>(
    _ value: T,
    at pointer: Pointer,
    using schema: Schema
  ) throws
  mutating func encode<T: ExplicitSchemaEncodable>(
    _ value: T,
    at pointer: Pointer,
    nestedIn parentSchema: Schema
  ) throws

  mutating func encode(_ value: Value, at pointer: Pointer) throws

  mutating func subEncode(at pointer: Pointer, _ body: (inout any SchemaEncoder) throws -> Void) throws

}


public protocol SchemaDecoder {

  mutating func decode(_ type: Value.Type, at pointer: Pointer) throws -> Value
  mutating func decode(_ requestedType: Bool.Type, at pointer: Pointer) throws -> Bool
  mutating func decode<I: FixedWidthInteger>(_ requestedType: I.Type, at pointer: Pointer) throws -> I
  mutating func decode(_ requestedType: BigInt.Type, at pointer: Pointer) throws -> BigInt
  mutating func decode(_ requestedType: BigUInt.Type, at pointer: Pointer) throws -> BigUInt
  mutating func decode<F: BinaryFloatingPoint>(_ requestedType: F.Type, at pointer: Pointer) throws -> F
  mutating func decode(_ requestedType: String.Type, at pointer: Pointer) throws -> String
  mutating func decode(_ requestedType: Data.Type, at pointer: Pointer) throws -> Data

  mutating func decode<T: SchemaDecodable>(_ requestedType: T.Type, at pointer: Pointer) throws -> T
  mutating func decode<T: ExplicitSchemaDecodable>(
    _ requestedType: T.Type,
    at pointer: Pointer,
    using schema: Schema
  ) throws -> T
  mutating func decode<T: ExplicitSchemaDecodable>(
    _ requestedType: T.Type,
    at pointer: Pointer,
    nestedIn schema: Schema
  ) throws -> T

  mutating func subDecode<R>(at pointer: Pointer, _ body: (inout SchemaDecoder) throws -> R) throws -> R

}


public protocol AssociatedSchema {

  static var schema: Schema { get }

}


func schema<T: SchemaEncodable>(of type: T.Type = T.self) -> Schema {
  type.schema
}

func schema<T: SchemaEncodable>(of value: T) -> Schema {
  schema(of: T.self)
}

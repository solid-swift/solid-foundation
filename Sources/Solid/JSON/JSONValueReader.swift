//
//  JSONReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/25/25.
//

import SolidData
import Foundation

public struct JSONValueReader: FormatReader {

  let tokenReader: JSONTokenReader

  public init(data: Data) {
    self.tokenReader = JSONTokenReader(data: data)
  }

  public init(string: String) {
    self.tokenReader = JSONTokenReader(string: string)
  }

  public var format: Format { JSON.format }

  public func read() throws -> Value {
    return try tokenReader.readValue(converter: ValueConverter.instance)
  }

  public func validateValue() throws {
    try tokenReader.readValue(converter: NullConverter.instance)
  }

  enum ValueConverter: JSONTokenConverter {

    case instance

    typealias ValueType = SolidData.Value

    func convertScalar(_ value: JSONToken.Scalar) throws -> Value {
      switch value {
      case .string(let string): .string(string)
      case .number(let number): .number(number.value)
      case .bool(let bool): .bool(bool)
      case .null: .null
      }
    }

    func convertArray(_ value: [Value]) throws -> Value {
      return .array(value)
    }

    func convertObject(_ value: [String: Value]) throws -> Value {
      return .object(Value.Object(uniqueKeysWithValues: value.map { (.string($0.key), $0.value) }))
    }

    func convertNull() -> Value {
      return .null
    }
  }

  enum NullConverter: JSONTokenConverter {

    case instance

    typealias ValueType = Void

    func convertScalar(_ value: JSONToken.Scalar) throws -> Void {
      return
    }

    func convertArray(_ value: [Void]) throws -> Void {
      return
    }

    func convertObject(_ value: [String: Void]) throws -> Void {
      return
    }

    func convertNull() -> Void {
      return
    }
  }
}

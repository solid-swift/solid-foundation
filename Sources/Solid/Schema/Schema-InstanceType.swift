//
//  SchemaType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/4/25.
//

import SolidData
import Foundation


extension Schema {

  public struct InstanceType {

    public var name: String
    public var valueType: ValueType

    public init(name: String, valueType: ValueType) {
      self.name = name
      self.valueType = valueType
    }

    public static let null = Self(name: "null", valueType: .null)
    public static let boolean = Self(name: "boolean", valueType: .bool)
    public static let integer = Self(name: "integer", valueType: .number)
    public static let number = Self(name: "number", valueType: .number)
    public static let bytes = Self(name: "bytes", valueType: .bytes)
    public static let string = Self(name: "string", valueType: .string)
    public static let array = Self(name: "array", valueType: .array)
    public static let object = Self(name: "object", valueType: .object)
  }

}

extension Schema.InstanceType: Sendable {}
extension Schema.InstanceType: Hashable {}
extension Schema.InstanceType: Equatable {}

extension Schema.InstanceType: CustomStringConvertible {

  public var description: String { name }

}

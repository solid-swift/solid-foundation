//
//  ValueType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/2/25.
//

public enum ValueType: String, CaseIterable {
  case null
  case bool
  case number
  case bytes
  case string
  case array
  case object
}

extension ValueType: Sendable {}
extension ValueType: Hashable {}
extension ValueType: Equatable {}

extension ValueType: CustomStringConvertible {

  public var description: String {
    switch self {
    case .null: "null"
    case .bool: "bool"
    case .number: "number"
    case .bytes: "bytes"
    case .string: "string"
    case .array: "array"
    case .object: "object"
    }
  }

}

extension Value {

  public var type: ValueType {
    switch self {
    case .null: .null
    case .bool: .bool
    case .number: .number
    case .bytes: .bytes
    case .string: .string
    case .array: .array
    case .object: .object
    case .tagged(tags: _, value: let value):
      value.type
    }
  }

}

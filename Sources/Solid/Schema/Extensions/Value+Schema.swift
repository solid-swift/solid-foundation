//
//  Values.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/9/25.
//

import SolidData
import SolidURI


extension Value {

  internal var schemaTypes: [Schema.InstanceType] {
    switch self {
    case .null: [.null]
    case .bool: [.boolean]
    case .number(let number): number.isInteger ? [.integer, .number] : [.number]
    case .bytes: [.bytes]
    case .string: [.string]
    case .array: [.array]
    case .object: [.object]
    case .tagged(tags: _, value: let value):
      value.schemaTypes
    }
  }

  internal static func schemaEqual(_ lhs: Value, _ rhs: Value) -> Bool {
    switch (lhs, rhs) {
    case (.null, .null):
      return true
    case (.bool(let lhs), .bool(let rhs)):
      return lhs == rhs
    case (.number(let lhs), .number(let rhs)):
      return lhs.decimal == rhs.decimal
    case (.string(let lhs), .string(let rhs)):
      return lhs == rhs
    case (.array(let lhs), .array(let rhs)):
      return lhs.elementsEqual(rhs, by: schemaEqual)
    case (.object(let lhs), .object(let rhs)):
      if Set(lhs.keys) != Set(rhs.keys) {
        return false
      }
      for (lkey, lvalue) in lhs {
        guard let rvalue = rhs[lkey] else {
          return false
        }
        if !schemaEqual(lvalue, rvalue) {
          return false
        }
      }
      return true
    case (.tagged(tags: _, value: let lhs), .tagged(tags: _, value: let rhs)):
      return schemaEqual(lhs, rhs)
    default:
      return false
    }
  }

  internal subscript(keyword: Schema.Keyword) -> Value? {
    get {
      guard case .object(let object) = self else {
        fatalError("Value is not an object")
      }
      return object[.string(keyword.rawValue)]
    }
    set {
      guard case .object(var object) = self else {
        fatalError("Value is not an object")
      }
      object[.string(keyword.rawValue)] = newValue
      self = .object(object)
    }
  }

  internal mutating func removeValue(forKeyword: Schema.Keyword) {
    guard case .object(var object) = self else {
      fatalError("Value is not an object")
    }
    object.removeValue(forKey: .string(forKeyword.rawValue))
    self = .object(object)
  }

  internal func schemaURI(requirements: URI.Requirement...) -> URI? {
    guard case .string(let string) = self else {
      return nil
    }
    return URI(encoded: string, requirements: Set(requirements))
  }

}

extension Value.Object {

  internal subscript(keyword: Schema.Keyword) -> Value? {
    get {
      self[.string(keyword.rawValue)]
    }
    set {
      self[.string(keyword.rawValue)] = newValue
    }
  }

  internal mutating func removeValue(forKeyword: Schema.Keyword) -> Value? {
    self.removeValue(forKey: .string(forKeyword.rawValue))
  }

}

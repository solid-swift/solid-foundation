//
//  BytesSchemas.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/25/25.
//

import SolidData
import SolidURI


extension Schema {

  public enum Bytes {

    public struct MinSize: AssertionBehavior, BuildableKeywordBehavior {

      public static let keyword: Keyword = .minSize

      public let minSize: Int

      public static func build(from schemaInstance: Value, context: inout Builder.Context) throws -> Self? {

        guard case .number(let minSizeInstance) = schemaInstance else {
          try context.invalidType(requiredType: .number)
        }

        guard let minSize: Int = minSizeInstance.int() else {
          try context.invalidValue("Must be an integer")
        }

        if minSize < 0 {
          try context.invalidValue("Must be greater than zero")
        }

        return Self(minSize: minSize)
      }

      public func prepare(parent: any SubSchema, context: inout Builder.Context) throws {

        if let maxSize = parent.behavior(MaxSize.self)?.maxSize {
          if minSize > maxSize {
            try context.invalidValue("Must be less than or equal to '\(Keyword.maxSize)'")
          }
        }
      }

      public func assert(instance: Value, context: inout Validator.Context) -> Assertion {

        guard let bytesInstance = instance.bytes else {
          return .valid
        }

        if bytesInstance.count < minSize {
          return .invalid("Must be a minimum of \(minSize) bytes")
        }

        return .valid
      }
    }

    public struct MaxSize: AssertionBehavior, BuildableKeywordBehavior {

      public static let keyword: Keyword = .maxSize

      public let maxSize: Int

      public static func build(from schemaInstance: Value, context: inout Builder.Context) throws -> Self? {

        guard case .number(let maxSizeInstance) = schemaInstance else {
          try context.invalidType(requiredType: .number)
        }

        guard let maxSize: Int = maxSizeInstance.int() else {
          try context.invalidValue("Must be an integer")
        }

        if maxSize < 0 {
          try context.invalidValue("Must be greater than zero")
        }

        return Self(maxSize: maxSize)
      }

      public func prepare(parent: any SubSchema, context: inout Builder.Context) throws {

        if let minSize = parent.behavior(MinSize.self)?.minSize {
          if maxSize < minSize {
            try context.invalidValue("Must be greater than or equal to \(Keyword.minSize)")
          }
        }
      }

      public func assert(instance: Value, context: inout Validator.Context) -> Assertion {

        guard let bytesInstance = instance.bytes else {
          return .valid
        }

        if bytesInstance.count > maxSize {
          return .invalid("Must be a maximum of \(maxSize) characters")
        }

        return .valid
      }
    }

  }
}

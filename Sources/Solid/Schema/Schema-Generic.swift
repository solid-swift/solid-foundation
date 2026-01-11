//
//  Schema-Generic.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/2/25.
//

import SolidData


extension Schema {

  public struct Generic {

    public struct Types: AssertionBehavior, BuildableKeywordBehavior {

      public static let keyword: Keyword = .type

      public let types: Set<InstanceType>

      public static func build(from keywordInstance: Value, context: inout Builder.Context) throws -> Self? {

        let typeStrings: [String]

        switch keywordInstance {
        case .string(let typeString):
          typeStrings = [typeString]
        case .array(let array):
          typeStrings = array.compactMap {
            guard case .string(let typeString) = $0 else { return nil }
            return typeString
          }
          if typeStrings.count != array.count {
            try context.invalidValue("Must contain only strings")
          }
          if typeStrings.isEmpty {
            try context.invalidValue("Must not be empty")
          }
          if Set(typeStrings).count != array.count {
            try context.invalidValue("Must be a unique")
          }
        default:
          try context.invalidType(requiredType: .string)
        }

        let types = try typeStrings.enumerated()
          .compactMap { (idx, typeString) in
            guard let type = context.metaSchema.types.first(where: { $0.name == typeString }) else {
              try context.invalidValue(options: context.metaSchema.types, at: idx)
            }
            return type
          }

        return Self(types: Set(types))
      }

      public func assert(instance: Value, context: inout Validator.Context) -> Assertion {

        guard !types.intersection(instance.schemaTypes).isEmpty else {
          return .invalid(options: types.map(\.name))
        }

        return .valid
      }

    }

    public struct Enum: AssertionBehavior, BuildableKeywordBehavior {

      public static let keyword: Keyword = .enum

      public let `enum`: [Value]

      public static func build(from schemaInstance: Value, context: inout Builder.Context) throws -> Self? {

        guard case .array(let enums) = schemaInstance else {
          try context.invalidType(requiredType: .array)
        }

        return Self(enum: enums)
      }

      public func assert(instance: Value, context: inout Validator.Context) -> Assertion {

        let anyEqual = self.enum.contains { Value.schemaEqual($0, instance) }

        if !anyEqual {
          return .invalid("Must be one of \(self.enum.map { "'\($0.stringified)'" })")
        }

        return .valid
      }
    }

    public struct Const: AssertionBehavior, BuildableKeywordBehavior {

      public static let keyword: Keyword = .const

      public let const: Value

      public func assert(instance: Value, context: inout Validator.Context) -> Assertion {

        let equal = Value.schemaEqual(self.const, instance)

        if !equal {
          return .invalid("Must be '\(self.const.stringified)'")
        }

        return .valid
      }

      public static func build(from schemaInstance: Value, context: inout Builder.Context) throws -> Self? {
        return Self(const: schemaInstance)
      }
    }
  }
}

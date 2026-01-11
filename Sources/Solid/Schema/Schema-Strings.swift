//
//  Schema-Strings.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/25/25.
//

import SolidData
import SolidURI


extension Schema {

  public enum Strings {

    public struct MinLength: AssertionBehavior, BuildableKeywordBehavior {

      public static let keyword: Keyword = .minLength

      public let minLength: Int

      public static func build(from schemaInstance: Value, context: inout Builder.Context) throws -> Self? {

        guard case .number(let minLengthInstance) = schemaInstance else {
          try context.invalidType(requiredType: .number)
        }

        guard let minLength: Int = minLengthInstance.int() else {
          try context.invalidValue("Must be an integer")
        }

        if minLength < 0 {
          try context.invalidValue("Must be greater than zero")
        }

        return Self(minLength: minLength)
      }

      public func prepare(parent: any SubSchema, context: inout Builder.Context) throws {

        if let maxLength = parent.behavior(MaxLength.self)?.maxLength {
          if minLength > maxLength {
            try context.invalidValue("Must be less than or equal to '\(Keyword.maxLength)'")
          }
        }
      }

      public func assert(instance: Value, context: inout Validator.Context) -> Assertion {

        guard let stringInstance = instance.string else {
          return .valid
        }

        if stringInstance.unicodeScalars.count < minLength {
          return .invalid("Must be a minimum of \(minLength) characters")
        }

        return .valid
      }
    }

    public struct MaxLength: AssertionBehavior, BuildableKeywordBehavior {

      public static let keyword: Keyword = .maxLength

      public let maxLength: Int

      public static func build(from schemaInstance: Value, context: inout Builder.Context) throws -> Self? {

        guard case .number(let maxLengthInstance) = schemaInstance else {
          try context.invalidType(requiredType: .number)
        }

        guard let maxLength: Int = maxLengthInstance.int() else {
          try context.invalidValue("Must be an integer")
        }

        if maxLength < 0 {
          try context.invalidValue("Must be greater than zero")
        }

        return Self(maxLength: maxLength)
      }

      public func prepare(parent: any SubSchema, context: inout Builder.Context) throws {

        if let minLength = parent.behavior(MinLength.self)?.minLength {
          if maxLength < minLength {
            try context.invalidValue("Must be greater than or equal to \(Keyword.minLength)")
          }
        }
      }

      public func assert(instance: Value, context: inout Validator.Context) -> Assertion {

        guard let stringInstance = instance.string else {
          return .valid
        }

        if stringInstance.unicodeScalars.count > maxLength {
          return .invalid("Must be a maximum of \(maxLength) characters")
        }

        return .valid
      }
    }

    public struct Pattern: AssertionBehavior, BuildableKeywordBehavior {

      public static let keyword: Keyword = .pattern

      public let pattern: Schema.Pattern

      public static func build(from schemaInstance: Value, context: inout Builder.Context) throws -> Self? {

        guard case .string(let stringInstance) = schemaInstance else {
          try context.invalidType(requiredType: .string)
        }

        guard let pattern = try? Schema.Pattern(pattern: stringInstance) else {
          try context.invalidValue("Must be a valid pattern")
        }

        return Self(pattern: pattern)
      }

      public func assert(instance: Value, context: inout Validator.Context) -> Assertion {

        guard let stringInstance = instance.string else {
          return .valid
        }

        if !pattern.matches(stringInstance) {
          return .invalid("Must match pattern /\(pattern.value)/")
        }

        return .valid
      }
    }

    public struct Format: KeywordBehavior, BuildableKeywordBehavior {

      public enum Mode: Sendable {
        case annotate
        case assert
      }

      public static let keyword: Keyword = .format
      public static let formatAssertionVocabularyId = MetaSchema.Draft2020_12.Vocabularies.formatAssertion.id

      public let formatType: FormatType
      public let mode: Mode

      public static func build(from schemaInstance: Value, context: inout Builder.Context) throws -> Self? {

        guard case .string(let format) = schemaInstance else {
          try context.invalidType(requiredType: .string)
        }

        let mode: Mode =
          if let override = context.options.formatModeOverride {
            override
          } else if context.schema.vocabularies.contains(where: { $0.key.id == Self.formatAssertionVocabularyId }) {
            .assert
          } else {
            .annotate
          }

        do {
          let formatType = try context.options.formatTypeLocator.locate(formatType: format)
          return Self(formatType: formatType, mode: mode)
        } catch {
          try context.invalidValue("Unrecognized format '\(format)'")
        }
      }

      public func apply(instance: Value, context: inout Schema.Validator.Context) -> Schema.Validation {

        guard case .string = instance else {
          return .valid
        }

        switch mode {
        case .annotate:
          return .annotation(.string(formatType.identifier))

        case .assert:
          let valid = formatType.validate(instance)
          return valid
            ? .annotation(.string(formatType.identifier))
            : .invalid("Must be a valid \(formatType.identifier)")
        }
      }
    }
  }
}

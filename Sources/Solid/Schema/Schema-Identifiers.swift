//
//  Schema-Identifiers.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/6/25.
//

import SolidData
import SolidURI
import OrderedCollections


extension Schema {

  public enum Identifiers {

    public static let anchorRegex = Pattern(valid: #"^[A-Za-z_][A-Za-z0-9._-]*$"#)

    public struct Id$: IdentifierBehavior, BuildableKeywordBehavior {

      public static let keyword: Schema.Keyword = .id$

      public let idRef: URI

      public static func process(from keywordInstance: Value, context: inout Builder.Context) throws {

        guard keywordInstance.type == .string else {
          try context.invalidType(requiredType: .string)
        }

        guard
          let idRef = keywordInstance.schemaURI(
            requirements: .kinds(.absolute, .relativeReference),
            .fragment(.disallowedOrEmpty),
            .normalized
          )
        else {
          try context.invalidValue("Must be a valid, normalized, URI-Reference")
        }

        context.idRef = idRef.removing(.fragment)
      }
    }

    public struct Schema$: IdentifierBehavior, BuildableKeywordBehavior {

      public static let keyword: Schema.Keyword = .schema$

      public let metaSchema: MetaSchema

      public static func process(from keywordInstance: Value, context: inout Builder.Context) throws {

        guard keywordInstance.type == .string else {
          try context.invalidType(requiredType: .string)
        }

        guard context.instanceLocation.parent == .root else {
          try context.invalidValue("'\(Keyword.schema$)' must be in a resource root schema")
        }

        guard let schemaId = keywordInstance.schemaURI(requirements: .kind(.absolute), .normalized) else {
          try context.invalidValue("Must be a valid, normalized, absolute URI")
        }

        do {

          if let metaSchema = try context.locate(metaSchemaId: schemaId) {
            context.metaSchema = metaSchema
            return
          }

          guard let subSchema = try context.locate(schemaId: schemaId) else {
            try context.invalidValue("Unresolved meta schema: \(schemaId)")
          }

          guard let schema = subSchema as? Schema else {
            try context.invalidValue("Meta schema must be a root (resource or embedded) schema")
          }

          context.metaSchema = MetaSchema.Builder.build(from: schema)

          return

        } catch let error as Error {
          throw error
        } catch {
          try context.invalidValue("Error resolving schema reference: '\(schemaId)': \(error.localizedDescription)")
        }
      }
    }

    public struct Anchor$: IdentifierBehavior, BuildableKeywordBehavior {

      public static let keyword: Schema.Keyword = .anchor$

      public let anchor: String

      public static func process(from keywordInstance: Value, context: inout Builder.Context) throws {

        guard let anchor = keywordInstance.string else {
          try context.invalidType(requiredType: .string)
        }

        guard anchorRegex.matches(anchor) else {
          try context.invalidValue("Must be a valid anchor name")
        }

        context.anchor = anchor

        return
      }

    }

    public struct DynamicAnchor$: IdentifierBehavior, BuildableKeywordBehavior {

      public static let keyword: Schema.Keyword = .dynamicAnchor$

      public static func process(from keywordInstance: Value, context: inout Builder.Context) throws {

        guard let anchor = keywordInstance.string else {
          try context.invalidType(requiredType: .string)
        }

        guard anchorRegex.matches(anchor) else {
          try context.invalidValue("Must be a valid anchor name")
        }

        context.dynamicAnchor = anchor
      }
    }

    public struct Vocabulary$: KeywordBehavior, BuildableKeywordBehavior {

      public static let keyword: Schema.Keyword = .vocabulary$

      public let vocabularies: OrderedDictionary<MetaSchema.Vocabulary, Bool>

      public static func build(from keywordInstance: Value, context: inout Builder.Context) throws -> Self? {

        guard let vocabularyIds = keywordInstance.object else {
          try context.invalidType(requiredType: .object)
        }

        guard context.instanceLocation.parent == .root else {
          try context.invalidValue("'\(Keyword.vocabulary$)' must be at the root of the schema")
        }

        let schema$ = context.scopeInstance[Keyword.schema$]
        guard schema$ != nil else {
          try context.invalidValue("'\(Keyword.vocabulary$)' may only be used in meta-schemas")
        }

        var vocabularies: OrderedDictionary<MetaSchema.Vocabulary, Bool> = [:]

        for (vocabularyIdx, (vocabularyIdInstance, requiredInstance)) in vocabularyIds.enumerated() {

          guard let vocabularyId = vocabularyIdInstance.schemaURI(requirements: .kind(.absolute), .normalized) else {
            try context.invalidValue("Must be a valid, normalized, absolute URI", at: vocabularyIdx)
          }

          guard case .bool(let required) = requiredInstance else {
            try context.invalidValue("Must be a boolean", at: vocabularyIdx, vocabularyId.encoded)
          }

          if let vocabulary = try context.locate(vocabularyId: vocabularyId) {
            vocabularies[vocabulary] = required
          } else if required {
            try context.invalidValue(
              "Required vocabulary '\(vocabularyId)' unresolved",
              at: vocabularyIdx,
              vocabularyId.encoded
            )
          }
        }

        return Self(vocabularies: vocabularies)
      }

      public func prepare(parent: any Schema.SubSchema, context: inout Schema.Builder.Context) throws {
      }

      public func apply(instance: Value, context: inout Schema.Validator.Context) -> Schema.Validation {
        return .valid
      }
    }
  }
}

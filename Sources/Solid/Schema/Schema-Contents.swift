//
//  Schema-Contents.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/9/25.
//

import SolidData


extension Schema {

  public enum Contents {

    public struct ContentMediaType: AnnotationBehavior, BuildableKeywordBehavior {

      public static let keyword: Schema.Keyword = .contentMediaType

      public let contentMediaType: String

      public static func build(from keywordInstance: Value, context: inout Builder.Context) throws -> Self? {

        guard case .string(let contentMediaType) = keywordInstance else {
          try context.invalidType(requiredType: .string)
        }

        return Self(contentMediaType: contentMediaType)
      }

      public func annotate(context: inout Validator.Context) -> Value? {
        return .string(contentMediaType)
      }
    }

    public struct ContentEncoding: AnnotationBehavior, BuildableKeywordBehavior {

      public static let keyword: Keyword = .contentEncoding

      public let contentEncoding: String

      public static func build(from keywordInstance: Value, context: inout Builder.Context) throws -> Self? {

        guard let stringInstance = keywordInstance.string else {
          try context.invalidType(requiredType: .string)
        }

        return Self(contentEncoding: stringInstance)
      }

      public func annotate(context: inout Validator.Context) -> Value? {
        return .string(contentEncoding)
      }
    }

    public struct ContentSchema: AnnotationBehavior, BuildableKeywordBehavior {

      public static let keyword: Keyword = .contentSchema

      public let subSchema: SubSchema

      public static func build(from keywordInstance: Value, context: inout Builder.Context) throws -> Self? {

        let subschema = try context.subSchema(for: keywordInstance)

        return Self(subSchema: subschema)
      }

      public func annotate(context: inout Validator.Context) -> Value? {
        return .string(subSchema.id.encoded)
      }
    }

  }

}

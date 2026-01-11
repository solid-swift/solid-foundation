//
//  MetaSchema.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/8/25.
//

import SolidURI
import Foundation
import OrderedCollections


/// MetaSchemas are schemas that define the behavior of other schemas.
///
/// A ``MetaSchema`` is the implementation of a meta-schema instance, like a ``Schema`` is the implementation
/// of a schema instance. The implementation provides the following:
///
/// - Mapping of locally defined instances types to their ``Schema/InstanceType``s.
/// - Mapping the keywords defined locally in the meta-schema to their ``Schema/KeywordBehavior``s.
/// - Composing the full list of keyword behaviors and instance types from the vocabularies.
/// - Definition of ``MetaSchema/Option``s that can be used to control the behavior of the schema.
/// - Runtime support for lookup of the meta-schema, it's vocabularies, and all associated schema instances.
///
public final class MetaSchema {

  /// Option for controlling the behavior of a schema.
  ///
  public protocol Option<Value>: Sendable {
    associatedtype Value: Sendable

    /// Unique URI of the option.
    var uri: URI { get }


    /// Retrieves this option's value from the given meta schema.
    ///
    /// - Parameter schema: The meta schema to get the value from.
    /// - Returns: The value for this option, or `nil` if no value is associated with this option
    /// in the provided schema.
    ///
    func from(schema: MetaSchema) -> Value?
  }

  /// Type of keyword used in MetaSchemas.
  public typealias Keyword = Schema.Keyword

  /// Id of the meta schema.
  public let id: URI
  /// List of referenced vocabularies.
  public let vocabularies: OrderedDictionary<Vocabulary, Bool>
  /// Instance types for types defined locally by the meta-schema.
  public let localTypes: OrderedSet<Schema.InstanceType>
  /// Instance types for types defined locally and by the vocabularies referenced by the meta-schema.
  public let types: OrderedSet<Schema.InstanceType>
  /// Keyword behaviors for keywords defined locally by the meta-schema.
  public let localKeywordBehaviors: OrderedDictionary<Schema.Keyword, any Schema.KeywordBehaviorBuilder.Type>
  /// Keyword behaviors for keywords defined locally and by the vocabularies referenced by the meta-schema.
  public let keywordBehaviors: OrderedDictionary<Schema.Keyword, any Schema.KeywordBehaviorBuilder.Type>
  /// Locator for schema instances associated with the meta-schema and vocabularies referenced by this meta-schema.
  public let schemaLocator: SchemaLocator
  /// Options for controlling the behavior of the schema.
  public let options: [URI: any Sendable]
  /// All keywords defined by this meta-schema and its referenced vocabuliaries.
  public let keywords: OrderedSet<Keyword>
  /// All indentifier related keywords defined by this meta-schema and its referenced vocabuliaries.
  public let identifierKeywords: OrderedSet<Keyword>
  /// All apllicator related keywords defined by this meta-schema and its referenced vocabuliaries.
  public let applicatorKeywords: OrderedSet<Keyword>
  /// All reservation related keywords defined by this meta-schema and its referenced vocabuliaries.
  public let reservedKeywords: OrderedSet<Keyword>

  /// Initializes a new ``MetaSchema`` instance.
  ///
  /// - Parameters:
  ///   - id: The unique identifier for the meta schema.
  ///   - vocabularies: The list of vocabularies referenced by this meta schema.
  ///   - localTypes: The instance types defined locally by this meta schema.
  ///   - localKeywordBehaviors: The keyword behaviors defined locally by this meta schema.
  ///   - schemaLocator: The locator for schema instances associated with this meta schema.
  ///   - options: The options for controlling the behavior of the schema.
  ///
  public init(
    id: URI,
    vocabularies: OrderedDictionary<Vocabulary, Bool>,
    localTypes: OrderedSet<Schema.InstanceType> = [],
    localKeywordBehaviors: OrderedDictionary<Keyword, any Schema.KeywordBehaviorBuilder.Type> = [:],
    schemaLocator: SchemaLocator,
    options: [URI: any Sendable] = [:]
  ) {
    self.id = id
    self.vocabularies = vocabularies
    self.localTypes = localTypes
    self.types = localTypes.union(OrderedSet(vocabularies.flatMap { Array($0.key.types) }))
    self.localKeywordBehaviors = localKeywordBehaviors
    self.keywordBehaviors = mergeBehaviors(local: localKeywordBehaviors, vocabularies: vocabularies.keys)
    self.options = options
    self.keywords = OrderedSet(keywordBehaviors.keys)
    self.schemaLocator = schemaLocator
    self.identifierKeywords = OrderedSet(
      self.keywordBehaviors.filter { $0.value is Schema.IdentifierBehavior.Type }.map { $0.key }
    )
    self.applicatorKeywords = OrderedSet(
      self.keywordBehaviors.filter { $0.value is Schema.ApplicatorBehavior.Type }.map { $0.key }
    )
    self.reservedKeywords = OrderedSet(
      self.keywordBehaviors.filter { $0.value is Schema.ReservedBehavior.Type }.map { $0.key }
    )

    func mergeBehaviors(
      local: OrderedDictionary<Schema.Keyword, any Schema.KeywordBehaviorBuilder.Type>,
      vocabularies: OrderedSet<Vocabulary>
    ) -> OrderedDictionary<Schema.Keyword, any Schema.KeywordBehaviorBuilder.Type> {
      var all = local
      for vocabulary in vocabularies {
        for (keyword, behavior) in vocabulary.keywordBehaviors {
          all[keyword] = behavior
        }
      }
      return all
    }
  }

  /// Finds the associated keyword behavior for the given keyword.
  ///
  /// - Parameter keyword: The keyword to find the behavior for.
  /// - Returns: The keyword behavior for the given keyword, or `nil` if no behavior is associated with the keyword.
  ///
  public func keywordBehavior(for keyword: Keyword) -> (any Schema.KeywordBehaviorBuilder.Type)? {
    return keywordBehaviors[keyword]
  }

  /// Returns the value for the given option.
  ///
  /// - Parameter option: The option to get the value for.
  /// - Returns: The value for the given option, or `nil` if no value is associated with the option.
  ///
  public func value<Value: Sendable, O: Option<Value>>(forOption option: O) -> Value? {
    return option.from(schema: self)
  }

  /// Returns a new ``MetaSchema`` with the given option applied.
  ///
  /// - Parameters:
  ///   - option: The option to apply.
  ///   - value: The value to set the option to.
  /// - Returns: A new ``MetaSchema`` with the given option applied.
  ///
  public func with<Value: Sendable, O: Option<Value>>(option: O, value: Value) -> MetaSchema {
    builder()
      .option(option, value: value)
      .build()
  }
}

extension MetaSchema: Sendable {}

extension MetaSchema: Hashable {

  /// Hashes the essential components of this meta schema by feeding them into the given hasher.
  ///
  /// - Parameter hasher: The hasher to use when combining the components of this meta schema.
  ///
  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

}

extension MetaSchema: Equatable {

  /// Returns a Boolean value indicating whether two meta schemas are equal.
  ///
  /// - Parameters:
  ///   - lhs: A meta schema to compare.
  ///   - rhs: Another meta schema to compare.
  /// - Returns: `true` if the two meta schemas are equal, `false` otherwise.
  ///
  public static func == (lhs: MetaSchema, rhs: MetaSchema) -> Bool {
    return lhs.id == rhs.id
  }

}

extension MetaSchema {

  private struct OptionDef<Value>: MetaSchema.Option {

    let uri: URI

    init(uri: URI) {
      self.uri = uri
    }
  }

  /// Defines a ``MetaSchema/Option``.
  ///
  /// - Parameters:
  ///  - baseId: The base URI for the option identifier. Must be an absolute URI.
  public static func option<Value: Sendable>(
    baseId id: URI,
    name: String,
    type: Value.Type = Value.self
  ) -> any Option<Value> {
    return MetaSchema.OptionDef<Value>(uri: id.updating(.fragment(name)))
  }
}

extension MetaSchema.Option {

  /// Retrieves this option's value from the given meta schema.
  ///
  /// - Parameter schema: The meta schema to get the value from.
  /// - Returns: The value for this option, or `nil` if no value is associated with this option.
  ///
  public func from(schema: MetaSchema) -> Value? {
    guard let value = schema.options[uri] as? Value else {
      return nil
    }
    return value
  }

}

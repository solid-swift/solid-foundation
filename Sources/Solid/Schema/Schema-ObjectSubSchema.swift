//
//  Schema-ObjectSchema.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/5/25.
//

import SolidData
import SolidURI
import OrderedCollections


extension Schema {

  public final class ObjectSubSchema: SubSchema {

    public typealias KeywordBehaviors = OrderedDictionary<Keyword, KeywordBehavior>

    public let id: URI
    public let keywordLocation: Pointer
    public let anchor: String?
    public let dynamicAnchor: String?

    public let instance: Value

    /// The schema's keyword behaviors, ordered by their ``Schema/KeywordBehavior/order``.
    public let keywordBehaviors: KeywordBehaviors

    /// The sub-scchemas that are descendants of this schema's.
    ///
    /// Descendant sub-schemas are any object or boolean schemas that are not themselves a resource
    /// root schema. This list allows for locating sub-schemas by their id, pointer, or anchors.
    public let subSchemas: [SubSchema]

    public init(
      id: URI,
      keywordLocation: Pointer,
      anchor: String?,
      dynamicAnchor: String?,
      instance: Value,
      keywordBehaviors: KeywordBehaviors,
      subSchemas: [SubSchema]
    ) {
      self.id = id
      self.keywordLocation = keywordLocation
      self.anchor = anchor
      self.dynamicAnchor = dynamicAnchor
      self.instance = instance
      self.keywordBehaviors = keywordBehaviors
      self.subSchemas = subSchemas
    }

    public func behavior<K: KeywordBehavior & BuildableKeywordBehavior>(_ type: K.Type) -> K? {

      guard let keywordBehavior = keywordBehaviors[K.keyword] else {
        return nil
      }

      guard let typedKeywordBehavior = keywordBehavior as? K else {
        fatalError("Invalid keyword behavior type: \(Swift.type(of: keywordBehavior))")
      }

      return typedKeywordBehavior
    }

    /// Builds a ``ObjectSubSchema`` from a schema instance.
    ///
    /// # Keyword Behaviors
    /// The keywords in each schema object are translated to ``KeywordBehavior`` instances. The building of the behaviors mutates the
    /// ``Schema/Builder/Context`` to share required information between behaviors and scopes. The order in which these behaviors are
    /// built is determined by their serialized order with the execption of identifier keywords (e.g., `$id`, `$anchor`, etc.) which are
    /// applied first; this allows the identity and meta-schema to be established before other keywords are processed.
    ///
    /// Keywords are built using ``Schema/Builder/Context/keywordBehavior(for:)`` for a specific keyword behavior type, with
    /// the behavior type determine by the ``MetaSchema/Vocabulary``. If a keyword is not found in the vocabulary, the behavior is
    /// determined by the ``Schema/Options/unknownProperties(_:)`` and related convenience methods like
    /// ``Schema/Options/ignoreUnknownProperties()``.
    ///
    public static func build(
      from schemaInstance: Value,
      context: inout Builder.Context,
      isUnknown: Bool = false
    ) throws -> ObjectSubSchema {

      guard let objectInstance = schemaInstance.object else {
        try context.invalidType(requiredType: .object)
      }

      var unappliedKeywords = OrderedSet(objectInstance.keys.compactMap(\.string).map(Keyword.init))

      // Apply identifier keywords (determined by current schema) first

      let presentIdentifierKeywords = unappliedKeywords.intersection(context.metaSchema.identifierKeywords)
      for identifierKeyword in presentIdentifierKeywords where unappliedKeywords.remove(identifierKeyword) != nil {

        if isUnknown && identifierKeyword == .id$ {
          // If this is an unknown context, we MUST NOT apply the id$ keyword
          continue
        }

        guard let idKeywordBehaviorType = context.metaSchema.keywordBehavior(for: identifierKeyword) else {
          continue
        }

        try context.keywordBehavior(for: idKeywordBehaviorType)
      }

      let reservedKeywords = unappliedKeywords.intersection(context.metaSchema.reservedKeywords)
      for reservedKeyword in reservedKeywords where unappliedKeywords.remove(reservedKeyword) != nil {

        guard let reservedKeywordBehaviorType = context.metaSchema.keywordBehavior(for: reservedKeyword) else {
          continue
        }

        try context.keywordBehavior(for: reservedKeywordBehaviorType)
      }

      // Apply all other keywords

      var unknownKeywords: [Keyword: KeywordBehavior] = [:]

      for keyword in unappliedKeywords {

        // Determine keyword behavior via schema / vocabulary

        if let keywordBehaviorType = context.metaSchema.keywordBehavior(for: keyword) {

          try context.keywordBehavior(for: keywordBehaviorType)

        } else {

          if let unknownSchemaObject = schemaInstance[keyword]?.object {

            // Unknown keywords that are objects are treated as sub-schemas

            let subSchema = try context.subSchema(for: .object(unknownSchemaObject), at: [keyword], isUnknown: true)

            unknownKeywords[keyword] = Applicators.Unknown(keyword: keyword, subSchema: subSchema)

          } else {

            // Handle unknown keywords based on schema options

            switch context.options.unknownKeywords {

            case .ignore:
              continue

            case .fail:
              throw Error.unknownKeyword(keyword.rawValue, location: context.instanceLocation)

            case .annotate:

              guard let annotationInstance = context.instance[keyword] else {
                // This should never happen, but just in case...
                continue
              }

              unknownKeywords[keyword] = Annotations.Unknown(keyword: keyword, annotation: annotationInstance)

            case .custom(let handler):

              guard let keywordInstance = context.instance[keyword] else {
                // This should never happen, but just in case...
                continue
              }

              let keywordLocation = context.instanceLocation / keyword

              // Determine custom behavior for unknown keyword, ignoring if nil is returned
              guard let customKeywordBehavior = try handler(keyword, keywordInstance, keywordLocation) else {
                continue
              }
              unknownKeywords[keyword] = customKeywordBehavior
            }
          }
        }
      }

      let keywordBehaviors = context.keywordBehaviors.sorted { $0.value.order < $1.value.order } + unknownKeywords

      return ObjectSubSchema(
        id: context.canonicalId,
        keywordLocation: context.schemaInstanceLocation,
        anchor: context.anchor,
        dynamicAnchor: context.dynamicAnchor,
        instance: schemaInstance,
        keywordBehaviors: OrderedDictionary(uniqueKeysWithValues: keywordBehaviors),
        subSchemas: context.subSchemas
      )
    }

    /// Validates an instance value against the schema object.
    ///
    /// The validation process iterates over each keyword behavior in the schema object and applies the behavior to the instance. The behaviors are
    /// sorted by their ``Schema/KeywordBehavior/order-5uly6`` and generally applied in that order. Additionally, behaviors can specify
    /// ``Schema/KeywordBehavior/dependencies-5uly6`` which are applied before the behavior that specifies them.
    public func validate(instance: Value, context: inout Validator.Context) -> Validation {

      var validations: [Validation] = []
      var appliedKeywords: Set<Keyword> = []

      func applyBehavior(for keyword: Keyword) {
        guard !appliedKeywords.contains(keyword), let behavior = keywordBehaviors[keyword] else {
          return
        }
        for dependency in behavior.dependencies {
          applyBehavior(for: dependency)
        }
        let validation = context.validate(instance: .inPlace(instance), using: behavior)
        validations.append(validation)
        appliedKeywords.insert(keyword)
      }

      for keyword in keywordBehaviors.keys {
        applyBehavior(for: keyword)
      }

      return validations.allSatisfy(\.isValid) ? .valid : .invalid
    }
  }
}

extension Schema.ObjectSubSchema: Schema.SubSchemaLocator {

  public func locate(fragment: String, allowing refTypes: Schema.RefTypes) -> (any Schema.SubSchema)? {
    assert(!refTypes.contains(.canonical), "Canonical reference type not allowed for fragment lookup")

    if isReferencingFragment(fragment, allowing: refTypes) {
      return self
    }

    for subSchema in subSchemas {

      // Resources are included in sub-schemas to allow them to be located. For scoped searches (e.g.,
      // anchor and dynamicAnchor) resources are "out of scope" and must not be considered.

      let subSchemaRefTypes = subSchema is Schema ? refTypes.subtracting([.anchor, .dynamicAnchor]) : refTypes

      if let located = subSchema.locate(fragment: fragment, allowing: subSchemaRefTypes) {
        return located
      }
    }

    return nil
  }

}

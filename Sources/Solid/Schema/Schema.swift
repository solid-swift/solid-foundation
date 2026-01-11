//
//  Schema.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/25/25.
//

import SolidData
import SolidURI
import Foundation
import OrderedCollections


public final class Schema {

  public let id: URI
  public let keywordLocation: Pointer
  public let anchor: String?
  public let dynamicAnchor: String?
  public let metaSchema: MetaSchema
  public let instance: Value
  public let subSchema: SubSchema
  public let resources: [Schema]

  internal init(
    id: URI,
    keywordLocation: Pointer,
    anchor: String?,
    dynamicAnchor: String?,
    metaSchema: MetaSchema,
    instance: Value,
    subSchema: SubSchema,
    resources: [Schema]
  ) {
    self.id = id
    self.keywordLocation = keywordLocation
    self.anchor = anchor
    self.dynamicAnchor = dynamicAnchor
    self.metaSchema = metaSchema
    self.instance = instance
    self.subSchema = subSchema
    self.resources = resources
  }

  public func validate(
    instance: Value,
    outputFormat: Schema.Validator.OutputFormat = .basic,
    options: Schema.Options = .default
  ) throws -> Validator.Result {

    let (result, _) = try Validator.validate(
      instance: instance,
      using: self,
      outputFormat: outputFormat,
      options: options
    )

    return result
  }

}

extension Schema: Sendable {}

extension Schema: Hashable {

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

}

extension Schema: Equatable {

  public static func == (lhs: Schema, rhs: Schema) -> Bool {
    lhs.id == rhs.id
  }

}

extension Schema: Schema.SubSchema {

  public func behavior<K>(_ type: K.Type) -> K? where K: KeywordBehavior & BuildableKeywordBehavior {
    subSchema.behavior(type)
  }

  public func validate(instance: Value, context: inout Validator.Context) -> Validation {
    subSchema.validate(instance: instance, context: &context)
  }

}

extension Schema: SchemaLocator {

  public func isRootSchemaReference(schemaId: URI) -> Bool {
    self.id == schemaId || self.id.removing(.fragment) == schemaId.removing(.fragment)
  }

  public func locate(schemaId: URI, options: Schema.Options) -> Schema? {

    if isRootSchemaReference(schemaId: schemaId) {

      return self

    }

    for resource in resources {
      if let schema = resource.locate(schemaId: schemaId, options: options) {
        return schema
      }
    }

    return nil
  }


  public func locate(fragment: String, allowing refTypes: RefTypes) -> SubSchema? {
    assert(!refTypes.contains(.canonical), "Canonical reference type not allowed for fragment lookup")

    if isReferencingFragment(fragment, allowing: refTypes) {
      return self
    }

    return subSchema.locate(fragment: fragment, allowing: refTypes)
  }

}

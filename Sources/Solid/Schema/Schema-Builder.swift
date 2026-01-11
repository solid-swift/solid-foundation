//
//  Schema-Builder.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/5/25.
//

import SolidCore
import SolidData
import SolidURI


extension Schema {

  public enum Builder {

    public static let defaultId = URI(encoded: "local://schema").neverNil()

    public typealias Keyword = Schema.Keyword

    private static let log = LogFactory.for(type: Self.self)

    public static func build(
      constant schemaInstance: Value,
      resourceId: URI = defaultId,
      options: Schema.Options = .default
    ) -> Schema {
      do {
        return try build(from: schemaInstance, resourceId: resourceId, options: options)
      } catch {
        fatalError("Failed to build schema: \(error)")
      }
    }

    public static func build(
      from schemaInstance: Value,
      resourceId: URI = defaultId,
      options: Schema.Options = .default
    ) throws -> Schema {

      let schemaLocator = CompositeSchemaLocator.from(locators: [
        options.defaultSchema.schemaLocator,
        options.schemaLocator,
      ])

      let buildOptions = options.schemaLocator(schemaLocator)

      var buildContext = Context(
        instance: schemaInstance,
        baseId: resourceId,
        options: buildOptions
      )

      guard let schema = try build(from: schemaInstance, context: &buildContext) as? Schema else {
        fatalError("Invalid schema type")
      }

      return schema
    }

    internal static func build(
      from schemaInstance: Value,
      context: inout Context,
      isUnknown: Bool = false
    ) throws -> SubSchema {

      let subSchema: SubSchema =
        switch schemaInstance {
        case .bool:
          try BooleanSubSchema.build(from: schemaInstance, context: &context)
        case .object:
          try ObjectSubSchema.build(from: schemaInstance, context: &context, isUnknown: isUnknown)
        default:
          try context.invalidValue(options: [Schema.InstanceType.object, Schema.InstanceType.boolean])
        }

      guard context.isResourceRoot || context.isRootScope else {
        return subSchema
      }
      // Schema defines an `id`, which implies it's a resource schema
      return Schema(
        id: context.canonicalId,
        keywordLocation: context.instanceLocation,
        anchor: context.anchor,
        dynamicAnchor: context.dynamicAnchor,
        metaSchema: context.metaSchema,
        instance: context.instance,
        subSchema: subSchema,
        resources: context.resources
      )

    }

    // Attempts to build a sub-schema from a fragment of a schema resource.
    //
    // Rules:
    // 1. The URI fragment must be a valid, non-empty, pointer
    // 2. The pointer must not resolve to an applicator keyword
    // 3. The resource must exist and be a JSON object
    // 4. The sub-schema cannot create a new scope (e.g., it cannot have an `id` keyword)
    //
    internal static func buildDynamicFragment(
      from schemaId: URI,
      context: inout Validator.Context
    ) throws -> SubSchema? {

      // Ensure it's a pointer fragment
      guard let fragment = schemaId.fragment, fragment.count > 1, let pointer = Pointer(encoded: fragment) else {
        return nil
      }

      // Ensure it's _not_ an applicator keyword
      let applicatorKeywords = context.currentScope.metaSchema.applicatorKeywords
      let pathKeyords = Set(pointer.map { Keyword(rawValue: $0.description) })
      guard pathKeyords.intersection(applicatorKeywords).isEmpty else {
        return nil
      }

      // Locate the resource schema, verify it's an object, and that it doesn't create a new scope
      guard
        let resourceSchema = try context.locateResource(schemaId: schemaId),
        case .object(let subSchemaInstance) = resourceSchema.instance[pointer]
      else {
        return nil
      }

      // Build the subschema
      do {

        var builderContext = Builder.Context(
          instance: .object(subSchemaInstance),
          baseId: context.baseId,
          options: context.options
        )

        return try Schema.ObjectSubSchema.build(
          from: .object(subSchemaInstance),
          context: &builderContext,
          isUnknown: true
        )

      } catch let e {
        log.error("Failed to build dynamic sub-schema for \(schemaId): \(e)")
        return nil
      }
    }
  }
}

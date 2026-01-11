//
//  Schema-Validator.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/7/25.
//

import SolidData


extension Schema {

  public enum Validator {

    public static func validate(
      instance: Value,
      using schema: Schema,
      outputFormat: Schema.Validator.OutputFormat = .basic,
      options: Schema.Options = .default
    ) throws -> (result: Validator.Result, annotations: [Schema.Annotation]) {

      let schemaLocator = CompositeSchemaLocator.from(
        locators: [
          schema.metaSchema.schemaLocator,
          options.schemaLocator,
        ]
        .compactMap(\.self)
      )

      let metaSchemaLocator = CompositeMetaSchemaLocator(locators: [
        options.metaSchemaLocator,
        MetaSchemaContainer(schemaLocator: schemaLocator),
      ])

      let validatorOptions =
        options
        .schemaLocator(schemaLocator)
        .metaSchemaLocator(metaSchemaLocator)

      var context = Validator.Context.root(
        instance: instance,
        schema: schema,
        outputFormat: outputFormat,
        options: validatorOptions
      )

      let validation = schema.validate(instance: instance, context: &context)

      let result = context.result(validation: validation)
      let annotations = context.annotations

      return (result, annotations)
    }

  }

}

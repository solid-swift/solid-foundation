//
//  MetaSchema-Draft-2020-12.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/5/25.
//

import SolidURI


extension MetaSchema {

  /// The JSON Schema Draft 2020-12 meta-schema.
  ///
  public static let v2020_12 = MetaSchema(
    id: Draft2020_12.id,
    vocabularies: [
      Draft2020_12.Vocabularies.core: true,
      Draft2020_12.Vocabularies.applicator: true,
      Draft2020_12.Vocabularies.validation: true,
      Draft2020_12.Vocabularies.unevaluated: true,
      Draft2020_12.Vocabularies.formatAnnotation: true,
      Draft2020_12.Vocabularies.content: true,
      Draft2020_12.Vocabularies.metadata: true,
    ],
    localKeywordBehaviors: [
      .dependencies: Schema.Objects.Dependencies.self
    ],
    schemaLocator: Draft2020_12.instance
  )

  /// The JSON Schema Draft 2020-12 meta-schema with the format assertion vocabulary.
  ///
  public static let v2020_12_formatAssertion = v2020_12.builder()
    .vocabularies(removing: [Draft2020_12.Vocabularies.formatAnnotation.id])
    .vocabularies(adding: [Draft2020_12.Vocabularies.formatAssertion: true])
    .build()

  /// Namespace for the JSON Schema Draft 2020-12 schema & meta-shema.
  ///
  public enum Draft2020_12: MetaSchemaLocator, SchemaLocator {
    case instance

    /// The URI of the JSON Schema Draft 2020-12 meta-schema.
    public static let id = URI(valid: "https://json-schema.org/draft/2020-12/schema")

    /// Options for the JSON Schema Draft 2020-12 meta-schema.
    public enum Options {

      /// Mode for format assertion.
      ///
      /// Format modes determine the behavior of format assertions:
      /// - ``Schema/Strings/Format/Mode/assert``: Validates the format and asserts it is valid.
      /// - ``Schema/Strings/Format/Mode/convert``: Converts the value to a related type. If
      /// successful, the result is annotated with the the format and the converted value. Otherwise,
      /// it records a failing assertion.
      ///
      public static let formatMode = MetaSchema.option(
        baseId: id,
        name: "formatMode",
        type: Schema.Strings.Format.Mode.self
      )
    }

    /// Locator for the JSON Schema Draft 2020-12 meta-schema.
    ///
    /// - Parameters:
    ///   - id: The URI of the meta-schema to locate. Must be equal ``MetaSchema/Draft2020_12/id``.
    ///   - options: The options to use when locating the meta-schema. These are ignored for this locator.
    /// - Returns: The meta-schema for the JSON Schema Draft 2020-12 schema, or `nil` if the id is not
    ///   equal to ``MetaSchema/Draft2020_12/id``.
    ///
    public func locate(metaSchemaId id: URI, options: Schema.Options) -> MetaSchema? {
      if id == Self.id {
        return .v2020_12
      }
      return nil
    }

    /// Locator for the JSON Schema Draft 2020-12 schema.
    ///
    /// - Parameters:
    ///   - id: The URI of the schema to locate. Must be equal ``MetaSchema/Draft2020_12/id``.
    ///   - options: The options to use when locating the schema. These are ignored for this locator.
    /// - Returns: The schema for the JSON Schema Draft 2020-12 schema, or `nil` if the id is not
    ///  equal to ``MetaSchema/Draft2020_12/id``.
    ///
    public func locate(schemaId id: URI, options: Schema.Options) -> Schema? {

      if id.removing(.fragment) == Self.id.removing(.fragment),
        let schema = Self.metaSchema.locate(schemaId: id, options: options)
      {
        return schema
      }

      return Vocabularies.instance.locate(schemaId: id, options: options)
    }

    /// Schema for the JSON Schema Draft 2020-12 meta-schema.
    public static let metaSchema = Schema.Builder.build(
      constant: [
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://json-schema.org/draft/2020-12/schema",
        "$vocabulary": [
          "https://json-schema.org/draft/2020-12/vocab/core": true,
          "https://json-schema.org/draft/2020-12/vocab/applicator": true,
          "https://json-schema.org/draft/2020-12/vocab/unevaluated": true,
          "https://json-schema.org/draft/2020-12/vocab/validation": true,
          "https://json-schema.org/draft/2020-12/vocab/meta-data": true,
          "https://json-schema.org/draft/2020-12/vocab/format-annotation": true,
          "https://json-schema.org/draft/2020-12/vocab/content": true,
        ],
        "$dynamicAnchor": "meta",
        "title": "Core and Validation specifications meta-schema",
        "allOf": [
          ["$ref": "meta/core"],
          ["$ref": "meta/applicator"],
          ["$ref": "meta/unevaluated"],
          ["$ref": "meta/validation"],
          ["$ref": "meta/meta-data"],
          ["$ref": "meta/format-annotation"],
          ["$ref": "meta/content"],
        ],
        "type": ["object", "boolean"],
        "$comment": """
          This meta-schema also defines keywords that have appeared in previous drafts
          in order to prevent incompatible extensions as they remain in common use.
        """,
        "properties": [
          "definitions": [
            "$comment": "\"definitions\" has been replaced by \"$defs\".",
            "type": "object",
            "additionalProperties": ["$dynamicRef": "#meta"],
            "deprecated": true,
            "default": [],
          ],
          "dependencies": [
            "$comment": """
              "dependencies" has been split and replaced by "dependentSchemas" and
              "dependentRequired" in order to serve their differing semantics.
            """,
            "type": "object",
            "additionalProperties": [
              "anyOf": [
                ["$dynamicRef": "#meta"],
                ["$ref": "meta/validation#/$defs/stringArray"],
              ]
            ],
            "deprecated": true,
            "default": [],
          ],
          "$recursiveAnchor": [
            "$comment": "\"$recursiveAnchor\" has been replaced by \"$dynamicAnchor\".",
            "$ref": "meta/core#/$defs/anchorString",
            "deprecated": true,
          ],
          "$recursiveRef": [
            "$comment": "\"$recursiveRef\" has been replaced by \"$dynamicRef\".",
            "$ref": "meta/core#/$defs/uriReferenceString",
            "deprecated": true,
          ],
        ],
      ],
      options: Schema.Options(
        defaultSchema: .v2020_12,
        unknownKeywords: .annotate,
        schemaLocator: Vocabularies.instance,
        metaSchemaLocator: Self.instance,
        vocabularyLocator: Vocabularies.instance,
        formatTypeLocator: FormatTypes(),
        contentMediaTypeLocator: ContentMediaTypeTypes(),
        contentEncodingLocator: ContentEncodingTypes(),
        collectAnnotations: .none
      )
    )

    /// Namespace for the JSON Schema Draft 2020-12 vocabularies.
    ///
    public enum Vocabularies: SchemaLocator, VocabularyLocator {
      case instance

      /// All of the vocabularies in the JSON Schema Draft 2020-12 specification.
      public static let all = [
        Self.core,
        Self.applicator,
        Self.validation,
        Self.unevaluated,
        Self.formatAnnotation,
        Self.formatAssertion,
        Self.content,
        Self.metadata,
      ]

      /// Schemas for all of the vocabularies in the JSON Schema Draft 2020-12 specification.
      public static let allSchemas = [
        Self.coreSchema,
        Self.applicatorSchema,
        Self.validationSchema,
        Self.unevaluatedSchema,
        Self.formatAnnotationSchema,
        Self.formatAssertionSchema,
        Self.contentSchema,
        Self.metadataSchema,
      ]

      /// Locators for vocabulary schemas in the JSON Schema Draft 2020-12 specification.
      ///
      /// - Parameters:
      ///   - id: The URI of the vocabulary to locate. Must be equal to one of the vocabulary IDs in the
      ///   JSON Schema Draft 2020-12 specification.
      ///   - options: The options to use when locating the vocabulary. These are ignored for this locator.
      /// - Returns: The vocabulary for the JSON Schema Draft 2020-12 specification, or `nil` if the id is not
      ///  equal to one of the vocabulary IDs in the JSON Schema Draft 2020-12 specification.
      ///
      public func locate(schemaId id: URI, options: Schema.Options) -> Schema? {
        for vocab in Self.allSchemas {
          if let schema = vocab.locate(schemaId: id, options: options) {
            return schema
          }
        }
        return nil
      }

      /// Locator for vocabulary schemas in the JSON Schema Draft 2020-12 specification.
      ///
      /// - Parameters:
      ///   - id: The URI of the vocabulary to locate. Must be equal to one of the vocabulary IDs in the
      ///   JSON Schema Draft 2020-12 specification.
      ///   - options: The options to use when locating the vocabulary. These are ignored for this locator.
      /// - Returns: The vocabulary for the JSON Schema Draft 2020-12 specification, or `nil` if the id is not
      /// equal to one of the vocabulary IDs in the JSON Schema Draft 2020-12 specification.
      ///
      public func locate(vocabularyId id: URI, options: Schema.Options) -> Vocabulary? {
        for vocabulary in Self.all where vocabulary.id == id {
          return vocabulary
        }
        return nil
      }

      /// The JSON Schema Draft 2020-12 **core** vocabulary.
      public static let core = Vocabulary(
        id: URI(valid: "https://json-schema.org/draft/2020-12/vocab/core"),
        keywordBehaviors: [
          Schema.Identifiers.Id$.self,
          Schema.Identifiers.Schema$.self,
          Schema.References.Ref$.self,
          Schema.Identifiers.Anchor$.self,
          Schema.References.DynamicRef$.self,
          Schema.Identifiers.DynamicAnchor$.self,
          Schema.Identifiers.Vocabulary$.self,
          Schema.Reservations.Comment$.self,
          Schema.Reservations.Defs$.self,
        ]
      )

      /// The JSON Schema Draft 2020-12 **core** vocabulary schema.
      public static let coreSchema = Schema.Builder.build(
        constant: [
          "$schema": "https://json-schema.org/draft/2020-12/schema",
          "$id": "https://json-schema.org/draft/2020-12/meta/core",
          "$dynamicAnchor": "meta",

          "title": "Core vocabulary meta-schema",
          "type": ["object", "boolean"],
          "properties": [
            "$id": [
              "$ref": "#/$defs/uriReferenceString",
              "$comment": "Non-empty fragments not allowed.",
              "pattern": "^[^#]*#?$",
            ],
            "$schema": ["$ref": "#/$defs/uriString"],
            "$ref": ["$ref": "#/$defs/uriReferenceString"],
            "$anchor": ["$ref": "#/$defs/anchorString"],
            "$dynamicRef": ["$ref": "#/$defs/uriReferenceString"],
            "$dynamicAnchor": ["$ref": "#/$defs/anchorString"],
            "$vocabulary": [
              "type": "object",
              "propertyNames": ["$ref": "#/$defs/uriString"],
              "additionalProperties": [
                "type": "boolean"
              ],
            ],
            "$comment": [
              "type": "string"
            ],
            "$defs": [
              "type": "object",
              "additionalProperties": ["$dynamicRef": "#meta"],
            ],
          ],
          "$defs": [
            "anchorString": [
              "type": "string",
              "pattern": "^[A-Za-z_][-A-Za-z0-9._]*$",
            ],
            "uriString": [
              "type": "string",
              "format": "uri",
            ],
            "uriReferenceString": [
              "type": "string",
              "format": "uri-reference",
            ],
          ],
        ],
        options: options
      )

      /// The JSON Schema Draft 2020-12 **applicator** vocabulary.
      public static let applicator = Vocabulary(
        id: URI(valid: "https://json-schema.org/draft/2020-12/vocab/applicator"),
        keywordBehaviors: [
          Schema.Arrays.PrefixItems.self,
          Schema.Arrays.Items.self,
          Schema.Arrays.Contains.self,
          Schema.Objects.AdditionalProperties.self,
          Schema.Objects.Properties.self,
          Schema.Objects.PatternProperties.self,
          Schema.Applicators.DependentSchemas.self,
          Schema.Objects.PropertyNames.self,
          Schema.Applicators.If.self,
          Schema.Applicators.Then.self,
          Schema.Applicators.Else.self,
          Schema.Applicators.AllOf.self,
          Schema.Applicators.AnyOf.self,
          Schema.Applicators.OneOf.self,
          Schema.Applicators.Not.self,
        ]
      )

      /// The JSON Schema Draft 2020-12 **applicator** vocabulary schema.
      public static let applicatorSchema = Schema.Builder.build(
        constant: [
          "$schema": "https://json-schema.org/draft/2020-12/schema",
          "$id": "https://json-schema.org/draft/2020-12/meta/applicator",
          "$dynamicAnchor": "meta",

          "title": "Applicator vocabulary meta-schema",
          "type": ["object", "boolean"],
          "properties": [
            "prefixItems": ["$ref": "#/$defs/schemaArray"],
            "items": ["$dynamicRef": "#meta"],
            "contains": ["$dynamicRef": "#meta"],
            "additionalProperties": ["$dynamicRef": "#meta"],
            "properties": [
              "type": "object",
              "additionalProperties": ["$dynamicRef": "#meta"],
              "default": [],
            ],
            "patternProperties": [
              "type": "object",
              "additionalProperties": ["$dynamicRef": "#meta"],
              "propertyNames": ["format": "regex"],
              "default": [],
            ],
            "dependentSchemas": [
              "type": "object",
              "additionalProperties": ["$dynamicRef": "#meta"],
              "default": [],
            ],
            "propertyNames": ["$dynamicRef": "#meta"],
            "if": ["$dynamicRef": "#meta"],
            "then": ["$dynamicRef": "#meta"],
            "else": ["$dynamicRef": "#meta"],
            "allOf": ["$ref": "#/$defs/schemaArray"],
            "anyOf": ["$ref": "#/$defs/schemaArray"],
            "oneOf": ["$ref": "#/$defs/schemaArray"],
            "not": ["$dynamicRef": "#meta"],
          ],
          "$defs": [
            "schemaArray": [
              "type": "array",
              "minItems": 1,
              "items": ["$dynamicRef": "#meta"],
            ]
          ],
        ],
        options: options
      )

      /// The JSON Schema Draft 2020-12 **validation** vocabulary.
      public static let validation = Vocabulary(
        id: URI(valid: "https://json-schema.org/draft/2020-12/vocab/validation"),
        types: [.array, .boolean, .integer, .null, .number, .object, .string],
        keywordBehaviors: [
          Schema.Generic.Types.self,
          Schema.Generic.Const.self,
          Schema.Generic.Enum.self,
          Schema.Numbers.MultipleOf.self,
          Schema.Numbers.Maximum.self,
          Schema.Numbers.ExclusiveMaximum.self,
          Schema.Numbers.Minimum.self,
          Schema.Numbers.ExclusiveMinimum.self,
          Schema.Strings.MaxLength.self,
          Schema.Strings.MinLength.self,
          Schema.Strings.Pattern.self,
          Schema.Arrays.MaxItems.self,
          Schema.Arrays.MinItems.self,
          Schema.Arrays.UniqueItems.self,
          Schema.Arrays.MaxContains.self,
          Schema.Arrays.MinContains.self,
          Schema.Objects.MaxProperties.self,
          Schema.Objects.MinProperties.self,
          Schema.Objects.Required.self,
          Schema.Objects.DependentRequired.self,
        ]
      )

      /// The JSON Schema Draft 2020-12 **validation** vocabulary schema.
      public static let validationSchema = Schema.Builder.build(
        constant: [
          "$schema": "https://json-schema.org/draft/2020-12/schema",
          "$id": "https://json-schema.org/draft/2020-12/meta/validation",
          "$dynamicAnchor": "meta",

          "title": "Validation vocabulary meta-schema",
          "type": ["object", "boolean"],
          "properties": [
            "type": [
              "anyOf": [
                ["$ref": "#/$defs/simpleTypes"],
                [
                  "type": "array",
                  "items": ["$ref": "#/$defs/simpleTypes"],
                  "minItems": 1,
                  "uniqueItems": true,
                ],
              ]
            ],
            "const": true,
            "enum": [
              "type": "array",
              "items": true,
            ],
            "multipleOf": [
              "type": "number",
              "exclusiveMinimum": 0,
            ],
            "maximum": [
              "type": "number"
            ],
            "exclusiveMaximum": [
              "type": "number"
            ],
            "minimum": [
              "type": "number"
            ],
            "exclusiveMinimum": [
              "type": "number"
            ],
            "maxLength": ["$ref": "#/$defs/nonNegativeInteger"],
            "minLength": ["$ref": "#/$defs/nonNegativeIntegerDefault0"],
            "pattern": [
              "type": "string",
              "format": "regex",
            ],
            "maxItems": ["$ref": "#/$defs/nonNegativeInteger"],
            "minItems": ["$ref": "#/$defs/nonNegativeIntegerDefault0"],
            "uniqueItems": [
              "type": "boolean",
              "default": false,
            ],
            "maxContains": ["$ref": "#/$defs/nonNegativeInteger"],
            "minContains": [
              "$ref": "#/$defs/nonNegativeInteger",
              "default": 1,
            ],
            "maxProperties": ["$ref": "#/$defs/nonNegativeInteger"],
            "minProperties": ["$ref": "#/$defs/nonNegativeIntegerDefault0"],
            "required": ["$ref": "#/$defs/stringArray"],
            "dependentRequired": [
              "type": "object",
              "additionalProperties": [
                "$ref": "#/$defs/stringArray"
              ],
            ],
          ],
          "$defs": [
            "nonNegativeInteger": [
              "type": "integer",
              "minimum": 0,
            ],
            "nonNegativeIntegerDefault0": [
              "$ref": "#/$defs/nonNegativeInteger",
              "default": 0,
            ],
            "simpleTypes": [
              "enum": [
                "array",
                "boolean",
                "integer",
                "null",
                "number",
                "object",
                "string",
              ]
            ],
            "stringArray": [
              "type": "array",
              "items": ["type": "string"],
              "uniqueItems": true,
              "default": [],
            ],
          ],
        ],
        options: options
      )

      /// The JSON Schema Draft 2020-12 **unevaluated** vocabulary.
      public static let unevaluated = Vocabulary(
        id: URI(valid: "https://json-schema.org/draft/2020-12/vocab/unevaluated"),
        keywordBehaviors: [
          Schema.Arrays.UnevaluatedItems.self,
          Schema.Objects.UnevaluatedProperties.self,
        ]
      )

      /// The JSON Schema Draft 2020-12 **unevaluated** vocabulary schema.
      public static let unevaluatedSchema = Schema.Builder.build(
        constant: [
          "$schema": "https://json-schema.org/draft/2020-12/schema",
          "$id": "https://json-schema.org/draft/2020-12/meta/unevaluated",
          "$dynamicAnchor": "meta",

          "title": "Unevaluated applicator vocabulary meta-schema",
          "type": ["object", "boolean"],
          "properties": [
            "unevaluatedItems": ["$dynamicRef": "#meta"],
            "unevaluatedProperties": ["$dynamicRef": "#meta"],
          ],
        ],
        options: options
      )

      /// The JSON Schema Draft 2020-12 **format annotation** vocabulary.
      public static let formatAnnotation = Vocabulary(
        id: URI(valid: "https://json-schema.org/draft/2020-12/vocab/format-annotation"),
        keywordBehaviors: [
          Schema.Annotations.Format.self
        ]
      )

      /// The JSON Schema Draft 2020-12 **format annotation** vocabulary schema.
      public static let formatAnnotationSchema = Schema.Builder.build(
        constant: [
          "$schema": "https://json-schema.org/draft/2020-12/schema",
          "$id": "https://json-schema.org/draft/2020-12/meta/format-annotation",
          "$dynamicAnchor": "meta",

          "title": "Format vocabulary meta-schema for annotation results",
          "type": ["object", "boolean"],
          "properties": [
            "format": ["type": "string"]
          ],
        ],
        options: options
      )

      /// The JSON Schema Draft 2020-12 **format assertion** vocabulary.
      public static let formatAssertion = Vocabulary(
        id: URI(valid: "https://json-schema.org/draft/2020-12/vocab/format-assertion"),
        keywordBehaviors: [
          Schema.Strings.Format.self
        ]
      )

      /// The JSON Schema Draft 2020-12 **format assertion** vocabulary schema.
      public static let formatAssertionSchema = Schema.Builder.build(
        constant: [
          "$schema": "https://json-schema.org/draft/2020-12/schema",
          "$id": "https://json-schema.org/draft/2020-12/meta/format-assertion",
          "$dynamicAnchor": "meta",

          "title": "Format vocabulary meta-schema for assertion results",
          "type": ["object", "boolean"],
          "properties": [
            "format": ["type": "string"]
          ],
        ],
        options: options
      )

      /// The JSON Schema Draft 2020-12 **content** vocabulary.
      public static let content = Vocabulary(
        id: URI(valid: "https://json-schema.org/draft/2020-12/vocab/content"),
        keywordBehaviors: [
          Schema.Contents.ContentMediaType.self,
          Schema.Contents.ContentEncoding.self,
          Schema.Contents.ContentSchema.self,
        ]
      )

      /// The JSON Schema Draft 2020-12 **content** vocabulary schema.
      public static let contentSchema = Schema.Builder.build(
        constant: [
          "$schema": "https://json-schema.org/draft/2020-12/schema",
          "$id": "https://json-schema.org/draft/2020-12/meta/content",
          "$dynamicAnchor": "meta",

          "title": "Content vocabulary meta-schema",
          "type": ["object", "boolean"],
          "properties": [
            "contentEncoding": ["type": "string"],
            "contentMediaType": ["type": "string"],
            "contentSchema": ["$dynamicRef": "#meta"],
          ],
        ],
        options: options
      )

      /// The JSON Schema Draft 2020-12 **meta-data** vocabulary.
      public static let metadata = Vocabulary(
        id: URI(valid: "https://json-schema.org/draft/2020-12/vocab/meta-data"),
        keywordBehaviors: [
          Schema.Annotations.Title.self,
          Schema.Annotations.Description.self,
          Schema.Annotations.Default.self,
          Schema.Annotations.Deprecated.self,
          Schema.Annotations.ReadOnly.self,
          Schema.Annotations.WriteOnly.self,
          Schema.Annotations.Examples.self,
        ]
      )

      /// The JSON Schema Draft 2020-12 **meta-data** vocabulary schema.
      public static let metadataSchema = Schema.Builder.build(
        constant: [
          "$schema": "https://json-schema.org/draft/2020-12/schema",
          "$id": "https://json-schema.org/draft/2020-12/meta/meta-data",
          "$dynamicAnchor": "meta",

          "title": "Meta-data vocabulary meta-schema",
          "type": ["object", "boolean"],
          "properties": [
            "title": [
              "type": "string"
            ],
            "description": [
              "type": "string"
            ],
            "default": true,
            "deprecated": [
              "type": "boolean",
              "default": false,
            ],
            "readOnly": [
              "type": "boolean",
              "default": false,
            ],
            "writeOnly": [
              "type": "boolean",
              "default": false,
            ],
            "examples": [
              "type": "array",
              "items": true,
            ],
          ],
        ],
        options: options
      )

      private static let options = Schema.Options(
        defaultSchema: .v2020_12,
        unknownKeywords: .annotate,
        schemaLocator: LocalSchemaContainer.empty,
        metaSchemaLocator: Draft2020_12.instance,
        vocabularyLocator: Draft2020_12.Vocabularies.instance,
        formatTypeLocator: FormatTypes(),
        contentMediaTypeLocator: ContentMediaTypeTypes(),
        contentEncodingLocator: ContentEncodingTypes(),
        collectAnnotations: .none
      )
    }
  }
}

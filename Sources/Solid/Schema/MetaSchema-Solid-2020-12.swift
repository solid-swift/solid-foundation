//
//  MetaSchema-Solid-v1-2020-12.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/5/25.
//

import SolidURI


extension MetaSchema {

  /// The Solid JSON Schema v1 (Draft 2020-12) meta-schema.
  ///
  public static let v1_2020_12_Solid = MetaSchema(
    id: Solid_v1_2020_12.id,
    vocabularies: [
      Draft2020_12.Vocabularies.core: true,
      Draft2020_12.Vocabularies.applicator: true,
      Draft2020_12.Vocabularies.validation: true,
      Draft2020_12.Vocabularies.unevaluated: true,
      Draft2020_12.Vocabularies.formatAnnotation: true,
      Draft2020_12.Vocabularies.content: true,
      Draft2020_12.Vocabularies.metadata: true,
      Solid_v1_2020_12.Vocabularies.bytesValidation: true,
      Solid_v1_2020_12.Vocabularies.coding: true,
    ],
    schemaLocator: Solid_v1_2020_12.instance
  )

  /// Namespace for the Solid JSON Schema v1 (Draft 2020-12) schema & meta-shema.
  ///
  public enum Solid_v1_2020_12: MetaSchemaLocator, SchemaLocator {
    case instance

    /// The URI of the Solid JSON Schema v1 (Draft 2020-12) meta-schema.
    public static let id = URI(valid: "https://github.com/solid-swift/draft/v1-2020-12/schema")

    /// Locator for the Solid JSON Schema v1 (Draft 2020-12) meta-schema.
    ///
    /// - Parameters:
    ///   - id: The URI of the meta-schema to locate. Must be equal ``MetaSchema/Solid2020_12/id``.
    ///   - options: The options to use when locating the meta-schema. These are ignored for this locator.
    /// - Returns: The meta-schema for the Solid JSON Schema v1 (Draft 2020-12) schema, or `nil` if
    ///   the id is not equal to ``MetaSchema/Solid2020_12/id``.
    ///
    public func locate(metaSchemaId id: URI, options: Schema.Options) -> MetaSchema? {
      if id == Self.id {
        return .v1_2020_12_Solid
      }
      return nil
    }

    /// Locator for the Solid JSON Schema v1 (Draft 2020-12) schema.
    ///
    /// - Parameters:
    ///   - id: The URI of the schema to locate. Must be equal ``MetaSchema/Solid_v1_2020_12/id``.
    ///   - options: The options to use when locating the schema. These are ignored for this locator.
    /// - Returns: The schema for the Solid JSON Schema v1 (Draft 2020-12) schema, or `nil` if
    ///   the id is not equal to ``MetaSchema/Solid_v1_2020_12/id``.
    ///
    public func locate(schemaId id: URI, options: Schema.Options) -> Schema? {

      if id.removing(.fragment) == Self.id.removing(.fragment),
         let schema = Self.metaSchema.locate(schemaId: id, options: options)
      {
        return schema
      }

      return Vocabularies.instance.locate(schemaId: id, options: options)
    }

    /// Schema for the Solid JSON Schema v1 (Draft 2020-12) meta-schema.
    public static let metaSchema = Schema.Builder.build(
      constant: [
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://github.com/solid-swift/draft/v1-2020-12/schema",
        "$vocabulary": [
          "https://json-schema.org/draft/2020-12/vocab/core": true,
          "https://json-schema.org/draft/2020-12/vocab/applicator": true,
          "https://json-schema.org/draft/2020-12/vocab/unevaluated": true,
          "https://json-schema.org/draft/2020-12/vocab/validation": true,
          "https://json-schema.org/draft/2020-12/vocab/meta-data": true,
          "https://json-schema.org/draft/2020-12/vocab/format-annotation": true,
          "https://json-schema.org/draft/2020-12/vocab/content": true,
          "https://github.com/solid-swift/draft/v1-2020-12/vocab/bytes-validation": true,
          "https://github.com/solid-swift/draft/v1-2020-12/vocab/coding": true,
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
          ["$ref": "meta/bytes-validation"],
          ["$ref": "meta/coding"],
        ],
        "type": ["object", "boolean"],
      ],
      options: Schema.Options(
        defaultSchema: .v1_2020_12_Solid,
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

    /// Namespace for the Solid JSON Schema v1 (Draft 2020-12) vocabularies.
    ///
    public enum Vocabularies: SchemaLocator, VocabularyLocator {
      case instance

      /// All of the vocabularies in the Solid JSON Schema v1 (Draft 2020-12) specification.
      public static let all = [
        Draft2020_12.Vocabularies.core,
        Draft2020_12.Vocabularies.applicator,
        Draft2020_12.Vocabularies.unevaluated,
        Draft2020_12.Vocabularies.validation,
        Draft2020_12.Vocabularies.metadata,
        Draft2020_12.Vocabularies.formatAnnotation,
        Draft2020_12.Vocabularies.content,
        Self.bytesValidation,
        Self.coding,
      ]

      /// Schemas for all of the vocabularies in the Solid JSON Schema v1 (Draft 2020-12) specification.
      public static let allSchemas = [
        Draft2020_12.Vocabularies.coreSchema,
        Draft2020_12.Vocabularies.applicatorSchema,
        Draft2020_12.Vocabularies.unevaluatedSchema,
        Draft2020_12.Vocabularies.validationSchema,
        Draft2020_12.Vocabularies.metadataSchema,
        Draft2020_12.Vocabularies.formatAnnotationSchema,
        Draft2020_12.Vocabularies.contentSchema,
        Self.bytesValidationSchema,
        Self.codingSchema,
      ]

      /// Locators for vocabulary schemas in the Solid JSON Schema v1 (Draft 2020-12) specification.
      ///
      /// - Parameters:
      ///   - id: The URI of the vocabulary to locate. Must be equal to one of the vocabulary IDs in the
      ///   Solid JSON Schema v1 (Draft 2020-12) specification.
      ///   - options: The options to use when locating the vocabulary. These are ignored for this locator.
      /// - Returns: The vocabulary for the Solid JSON Schema v1 (Draft 2020-12) specification, or `nil`
      ///   if the id is not equal to one of the vocabulary IDs in the Solid JSON Schema v1 (Draft 2020-12)
      ///   specification.
      ///
      public func locate(schemaId id: URI, options: Schema.Options) -> Schema? {
        for vocab in Self.allSchemas {
          if let schema = vocab.locate(schemaId: id, options: options) {
            return schema
          }
        }
        return nil
      }

      /// Locator for vocabulary schemas in the Solid JSON Schema v1 (Draft 2020-12) specification.
      ///
      /// - Parameters:
      ///   - id: The URI of the vocabulary to locate. Must be equal to one of the vocabulary IDs in the
      ///   Solid JSON Schema v1 (Draft 2020-12) specification.
      ///   - options: The options to use when locating the vocabulary. These are ignored for this locator.
      /// - Returns: The vocabulary for the Solid JSON Schema v1 (Draft 2020-12) specification, or `nil`
      ///   if the id is not equal to one of the vocabulary IDs in the Solid JSON Schema v1 (Draft 2020-12)
      ///   specification.
      ///
      public func locate(vocabularyId id: URI, options: Schema.Options) -> Vocabulary? {
        for vocabulary in Self.all where vocabulary.id == id {
          return vocabulary
        }
        return nil
      }

      /// The Solid JSON Schema 2020-12 **bytes-validation** vocabulary.
      public static let bytesValidation = Vocabulary(
        id: URI(valid: "https://github.com/solid-swift/draft/v1-2020-12/vocab/bytes-validation"),
        types: [.bytes],
        keywordBehaviors: [
          Schema.Bytes.MinSize.self,
          Schema.Bytes.MaxSize.self,
        ]
      )

      /// The Solid JSON Schema 2020-12 **bytes-validation** vocabulary meta-schema.
      public static let bytesValidationSchema = Schema.Builder.build(
        constant: [
          "$schema": "https://json-schema.org/draft/2020-12/schema",
          "$id": "https://github.com/solid-swift/draft/v1-2020-12/meta/bytes-validation",
          "$dynamicAnchor": "meta",

          "title": "Solid Schema v1 Validation Vocabulary (Draft 2020-12).",
          "type": ["object"],
          "additionalProperties": true,

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

            "maxSize": ["$ref": "#/$defs/nonNegativeInteger"],
            "minSize": ["$ref": "#/$defs/nonNegativeIntegerDefault0"],
          ],
          "$defs": [
            "simpleTypes": [
              "enum": [
                "array",
                "boolean",
                "bytes",
                "integer",
                "null",
                "number",
                "object",
                "string",
              ]
            ],
            "nonNegativeInteger": [
              "type": "integer",
              "minimum": 0,
            ],
            "nonNegativeIntegerDefault0": [
              "$ref": "#/$defs/nonNegativeInteger",
              "default": 0,
            ],
          ],
        ],
        options: options
      )

      /// The Solid JSON Schema 2020-12 **coding** vocabulary.
      public static let coding = Vocabulary(
        id: URI(valid: "https://github.com/solid-swift/draft/v1-2020-12/vocab/coding"),
        keywordBehaviors: [
          Schema.SolidCoding.Units.self,
          Schema.SolidCoding.BitWidth.self,
        ]
      )

      /// The Solid JSON Schema 2020-12 **coding** vocabulary meta-schema.
      public static let codingSchema = Schema.Builder.build(
        constant: [
          "$schema": "https://json-schema.org/draft/2020-12/schema",
          "$id": "https://github.com/solid-swift/draft/v1-2020-12/meta/coding",
          "$dynamicAnchor": "meta",

          "title": "Solid Schema v1 Coding Vocabulary (Draft 2020-12).",
          "type": ["object"],
          "additionalProperties": true,

          "properties": [
            // “Coding vocabulary” companion keywords (only meaningful for certain formats).
            "units": ["$ref": "#/$defs/UnitsKeyword"],
            "bitWidth": ["$ref": "#/$defs/BitWidthKeyword"],
            "contentEncoding": ["type": "string"],
          ],

          // Apply conditional constraints only when `format` is present (or companion
          // keywords are used).
          "allOf": [
            // If a companion keyword is present, require `format` to be present.
            [
              "if": [
                "anyOf": [
                  ["required": ["units"]],
                  ["required": ["bitWidth"]],
                  ["required": ["contentEncoding"]],
                ]
              ],
              "then": [
                "required": ["format"]
              ],
            ],

            // Gate: `units` is only allowed for time-related formats.
            [
              "if": ["required": ["units"]],
              "then": [
                "properties": [
                  "format": [
                    "enum": [
                      "instant",
                      "local-time", "local-date", "local-date-time",
                      "offset-time", "offset-date-time",
                      "zoned-time", "zoned-date-time",
                      "interval",
                      "duration",
                    ]
                  ]
                ],
                "required": ["format"],
              ],
            ],

            // Gate: `bitWidth` is only allowed for numeric formats.
            [
              "if": ["required": ["bitWidth"]],
              "then": [
                "properties": [
                  "format": [
                    "enum": ["integer", "float", "decimal"]
                  ]
                ],
                "required": ["format"],
              ],
            ],

            // Dispatch to per-format specs
            ["$ref": "#/$defs/NumberSpecDispatch"],
            ["$ref": "#/$defs/TimeSpecDispatch"],
            ["$ref": "#/$defs/UUIDSpecDispatch"],
            ["$ref": "#/$defs/NetworkAndTextSpecDispatch"],
          ],

          "$defs": [
            // --- Shared keyword schemas ------------------------------------------------

            "UnitsKeyword": [
              "type": ["string"],
              "enum": ["seconds", "milliseconds", "microseconds", "nanoseconds", "days"],
            ],

            "BitWidthKeyword": [
              "description": "Bit width for numeric formats when explicitly declared.",
              "type": ["integer", "string"],
              "enum": [8, 16, 32, 64, 128, "big"],
            ],

            // --- Dispatch blocks -------------------------------------------------------

            "NumberSpecDispatch": [
              "allOf": [
                [
                  "if": [
                    "properties": ["format": ["enum": ["integer", "float", "decimal"]]],
                    "required": ["format"],
                  ],
                  "then": ["$ref": "#/$defs/NumberSpec"],
                ]
              ]
            ],

            "TimeSpecDispatch": [
              "allOf": [
                [
                  "if": [
                    "properties": [
                      "format": [
                        "enum": [
                          "instant",
                          "local-time", "local-date", "local-date-time",
                          "offset-time", "offset-date-time",
                          "zoned-time", "zoned-date-time",
                          "interval", "period", "duration",
                        ]
                      ]
                    ],
                    "required": ["format"],
                  ],
                  "then": ["$ref": "#/$defs/TimeSpec"],
                ]
              ]
            ],

            "UUIDSpecDispatch": [
              "allOf": [
                [
                  "if": [
                    "properties": ["format": ["enum": ["uuid"]]],
                    "required": ["format"],
                  ],
                  "then": ["$ref": "#/$defs/UUIDSpec"],
                ]
              ]
            ],

            "NetworkAndTextSpecDispatch": [
              "allOf": [
                [
                  "if": [
                    "properties": [
                      "format": [
                        "enum": [
                          "uri", "uri-reference", "iri", "iri-reference", "uri-template",
                          "json-pointer", "relative-json-pointer",
                          "regex",
                          "email", "idn-email",
                          "hostname", "idn-hostname",
                          "ipv4", "ipv6",
                        ]
                      ]
                    ],
                    "required": ["format"],
                  ],
                  "then": ["$ref": "#/$defs/NetworkAndTextSpec"],
                ]
              ]
            ],

            // Numeric instant duration since epoch (integer/number) – relies on TimeSpec for `instant`
            "InstantNumericItemSchema": [
              "description":
                "Schema object for tuple element representing duration since epoch (instant numeric form).",
              "type": ["object"],
              "additionalProperties": true,
              "properties": [
                "format": ["const": "instant"],
                "type": [
                  "anyOf": [
                    ["const": "integer"],
                    ["const": "number"],
                    [
                      "type": ["array"],
                      "contains": ["enum": ["integer", "number"]],
                    ],
                  ]
                ],
                // allow units; defaulting happens in TimeSpec for instant numeric
                "units": ["$ref": "#/$defs/UnitsKeyword"],
              ],
              "required": ["format"],
            ],

            // Numeric local-time duration since midnight (integer/number) – relies on TimeSpec for `local-time`
            "LocalTimeNumericItemSchema": [
              "description":
                "Schema object for tuple element representing duration since midnight (local-time numeric form).",
              "type": ["object"],
              "additionalProperties": true,
              "properties": [
                "format": ["const": "local-time"],
                "type": [
                  "anyOf": [
                    ["const": "integer"],
                    ["const": "number"],
                    [
                      "type": ["array"],
                      "contains": ["enum": ["integer", "number"]],
                    ],
                  ]
                ],
                "units": ["$ref": "#/$defs/UnitsKeyword"],
              ],
              "required": ["format"],
            ],

            "OffsetSecondsItemSchema": [
              "description": "Schema object for tuple element representing UTC offset in seconds.",
              "type": ["object"],
              "additionalProperties": true,
              "properties": [
                "type": [
                  "anyOf": [
                    ["const": "integer"],
                    [
                      "type": ["array"],
                      "contains": ["const": "integer"],
                    ],
                  ]
                ],
                "minimum": ["default": -64800],    // -18:00
                "maximum": ["default": 64800],    // +18:00
              ],
            ],

            "ZoneIdItemSchema": [
              "description": "Schema object for tuple element representing a time-zone id (typically IANA TZDB name).",
              "type": ["object"],
              "additionalProperties": true,
              "properties": [
                "type": [
                  "anyOf": [
                    ["const": "string"],
                    [
                      "type": ["array"],
                      "contains": ["const": "string"],
                    ],
                  ]
                ],
                // Optional: if you adopt a Solid format name for zones later, you can tighten this.
                "format": ["default": "iana-time-zone"],
              ],
            ],

            // --- Concrete specs --------------------------------------------------------

            "NumberSpec": [
              "description": """
                Integer, Float, or Decimal number.
              """,
              "type": ["object"],
              "additionalProperties": true,

              "allOf": [
                // integer
                [
                  "if": [
                    "properties": ["format": ["const": "integer"]],
                    "required": ["format"],
                  ],
                  "then": [
                    // type must include integer or number (some schemas use number for all numeric)
                    "allOf": [
                      [
                        "anyOf": [
                          ["properties": ["type": ["const": "integer"]], "required": ["type"]],
                          ["properties": ["type": ["const": "number"]], "required": ["type"]],
                          [
                            "properties": ["type": ["type": ["array"], "contains": ["enum": ["integer", "number"]]]],
                            "required": ["type"],
                          ],
                          ["not": ["required": ["type"]]],    // allow omitted type (freeform schemas)
                        ]
                      ]
                    ],
                    "properties": [
                      "bitWidth": [
                        "enum": [8, 16, 32, 64, 128, "big"],
                        "default": "big"
                      ]
                    ],
                  ],
                ],

                // float
                [
                  "if": ["properties": ["format": ["const": "float"]], "required": ["format"]],
                  "then": [
                    "anyOf": [
                      ["properties": ["type": ["const": "number"]], "required": ["type"]],
                      [
                        "properties": ["type": ["type": ["array"], "contains": ["const": "number"]]],
                        "required": ["type"],
                      ],
                      ["not": ["required": ["type"]]],
                    ],
                    "properties": [
                      "bitWidth": [
                        "enum": [16, 32, 64],
                        "default": 64,
                      ]
                    ],
                  ],
                ],

                // decimal
                [
                  "if": ["properties": ["format": ["const": "decimal"]], "required": ["format"]],
                  "then": [
                    // decimal is commonly a string in text; in Solid (Value) you may also allow bytes/binary forms.
                    "anyOf": [
                      ["properties": ["type": ["const": "string"]], "required": ["type"]],
                      ["properties": ["type": ["const": "number"]], "required": ["type"]],
                      [
                        "properties": ["type": ["type": ["array"], "contains": ["enum": ["string", "number"]]]],
                        "required": ["type"],
                      ],
                      ["not": ["required": ["type"]]],
                    ],
                    "properties": [
                      "bitWidth": [
                        "enum": [32, 64, 128, "big"],
                        "default": "big",
                      ]
                    ],
                  ],
                ],
              ],
            ],

            "TimeSpec": [
              "description": """
                Time-related logical formats.
              
                Validates:
                - schema.keyword `format`
                - schema.keyword `type`
                - schema.keyword `units` (for numeric/tuple representations)
                - tuple array shapes via `prefixItems` for offset/zoned formats
              """,
              "type": ["object"],
              "additionalProperties": true,

              "allOf": [
                // instant
                [
                  "if": ["properties": ["format": ["const": "instant"]], "required": ["format"]],
                  "then": [
                    "anyOf": [
                      ["properties": ["type": ["const": "string"]], "required": ["type"]],
                      ["properties": ["type": ["const": "number"]], "required": ["type"]],
                      ["properties": ["type": ["const": "integer"]], "required": ["type"]],
                      [
                        "properties": [
                          "type": ["type": ["array"], "contains": ["enum": ["string", "number", "integer"]]]
                        ], "required": ["type"],
                      ],
                      ["not": ["required": ["type"]]],
                    ],
                    "allOf": [
                      [
                        "if": [
                          "anyOf": [
                            ["properties": ["type": ["const": "integer"]], "required": ["type"]],
                            [
                              "properties": ["type": ["type": ["array"], "contains": ["const": "integer"]]],
                              "required": ["type"],
                            ],
                          ]
                        ],
                        "then": [
                          "properties": ["units": ["default": "milliseconds"]]
                        ],
                      ],
                      [
                        "if": [
                          "anyOf": [
                            ["properties": ["type": ["const": "number"]], "required": ["type"]],
                            [
                              "properties": ["type": ["type": ["array"], "contains": ["const": "number"]]],
                              "required": ["type"],
                            ],
                          ]
                        ],
                        "then": [
                          "properties": ["units": ["default": "seconds"]]
                        ],
                      ],
                    ],
                  ],
                ],

                // local-time
                [
                  "if": ["properties": ["format": ["const": "local-time"]], "required": ["format"]],
                  "then": [
                    "anyOf": [
                      ["properties": ["type": ["const": "string"]], "required": ["type"]],
                      ["properties": ["type": ["const": "number"]], "required": ["type"]],
                      ["properties": ["type": ["const": "integer"]], "required": ["type"]],
                      [
                        "properties": [
                          "type": ["type": ["array"], "contains": ["enum": ["string", "number", "integer"]]]
                        ], "required": ["type"],
                      ],
                      ["not": ["required": ["type"]]],
                    ],
                    "allOf": [
                      [
                        "if": [
                          "anyOf": [
                            ["properties": ["type": ["const": "integer"]], "required": ["type"]],
                            [
                              "properties": ["type": ["type": ["array"], "contains": ["const": "integer"]]],
                              "required": ["type"],
                            ],
                          ]
                        ],
                        "then": [
                          "properties": ["units": ["default": "milliseconds"]]
                        ],
                      ]
                    ],
                  ],
                ],

                // local-date
                [
                  "if": ["properties": ["format": ["const": "local-date"]], "required": ["format"]],
                  "then": [
                    "anyOf": [
                      ["properties": ["type": ["const": "string"]], "required": ["type"]],
                      ["properties": ["type": ["const": "integer"]], "required": ["type"]],
                      [
                        "properties": ["type": ["type": ["array"], "contains": ["enum": ["string", "integer"]]]],
                        "required": ["type"],
                      ],
                      ["not": ["required": ["type"]]],
                    ],
                    "allOf": [
                      [
                        "if": [
                          "anyOf": [
                            ["properties": ["type": ["const": "integer"]], "required": ["type"]],
                            [
                              "properties": ["type": ["type": ["array"], "contains": ["const": "integer"]]],
                              "required": ["type"],
                            ],
                          ]
                        ],
                        "then": [
                          "properties": ["units": ["default": "days"]]
                        ],
                      ]
                    ],
                  ],
                ],

                // offset-time
                [
                  "if": ["properties": ["format": ["const": "offset-time"]], "required": ["format"]],
                  "then": [
                    "anyOf": [
                      ["properties": ["type": ["const": "string"]], "required": ["type"]],
                      ["properties": ["type": ["const": "array"]], "required": ["type"]],
                      [
                        "properties": ["type": ["type": ["array"], "contains": ["enum": ["string", "array"]]]],
                        "required": ["type"],
                      ],
                      ["not": ["required": ["type"]]],
                    ],
                    "properties": [
                      "units": ["default": "nanoseconds"]
                    ],
                    // If array is allowed, enforce tuple shape via prefixItems
                    "allOf": [
                      [
                        "if": [
                          "anyOf": [
                            ["properties": ["type": ["const": "array"]], "required": ["type"]],
                            [
                              "properties": ["type": ["type": ["array"], "contains": ["const": "array"]]],
                              "required": ["type"],
                            ],
                            ["not": ["required": ["type"]]],    // freeform schemas might still choose array
                          ]
                        ],
                        "then": [
                          "properties": [
                            "prefixItems": [
                              "type": ["array"],
                              "minItems": 2,
                              "maxItems": 2,
                              "prefixItems": [
                                ["$ref": "#/$defs/LocalTimeNumericItemSchema"],
                                ["$ref": "#/$defs/OffsetSecondsItemSchema"],
                              ],
                              "items": false,
                              "default": [
                                ["format": "local-time", "type": "integer", "units": "nanoseconds"],
                                ["type": "integer", "minimum": -64800, "maximum": 64800],
                              ],
                            ],
                            "minItems": ["default": 2],
                            "maxItems": ["default": 2],
                            "items": ["default": false],
                          ]
                        ],
                      ]
                    ],
                  ],
                ],

                // offset-date-time
                [
                  "if": ["properties": ["format": ["const": "offset-date-time"]], "required": ["format"]],
                  "then": [
                    "anyOf": [
                      ["properties": ["type": ["const": "string"]], "required": ["type"]],
                      ["properties": ["type": ["const": "array"]], "required": ["type"]],
                      [
                        "properties": ["type": ["type": ["array"], "contains": ["enum": ["string", "array"]]]],
                        "required": ["type"],
                      ],
                      ["not": ["required": ["type"]]],
                    ],
                    "properties": [
                      "units": ["default": "nanoseconds"]
                    ],
                    "allOf": [
                      [
                        "if": [
                          "anyOf": [
                            ["properties": ["type": ["const": "array"]], "required": ["type"]],
                            [
                              "properties": ["type": ["type": ["array"], "contains": ["const": "array"]]],
                              "required": ["type"],
                            ],
                            ["not": ["required": ["type"]]],
                          ]
                        ],
                        "then": [
                          "properties": [
                            "prefixItems": [
                              "type": ["array"],
                              "minItems": 2,
                              "maxItems": 2,
                              "prefixItems": [
                                ["$ref": "#/$defs/InstantNumericItemSchema"],
                                ["$ref": "#/$defs/OffsetSecondsItemSchema"],
                              ],
                              "items": false,
                              "default": [
                                ["format": "instant", "type": "integer", "units": "nanoseconds"],
                                ["type": "integer", "minimum": -64800, "maximum": 64800],
                              ],
                            ],
                            "minItems": ["default": 2],
                            "maxItems": ["default": 2],
                            "items": ["default": false],
                          ]
                        ],
                      ]
                    ],
                  ],
                ],

                // zoned-time
                [
                  "if": ["properties": ["format": ["const": "zoned-time"]], "required": ["format"]],
                  "then": [
                    "anyOf": [
                      ["properties": ["type": ["const": "string"]], "required": ["type"]],
                      ["properties": ["type": ["const": "array"]], "required": ["type"]],
                      [
                        "properties": ["type": ["type": ["array"], "contains": ["enum": ["string", "array"]]]],
                        "required": ["type"],
                      ],
                      ["not": ["required": ["type"]]],
                    ],
                    "properties": [
                      "units": ["default": "nanoseconds"]
                    ],
                    "allOf": [
                      [
                        "if": [
                          "anyOf": [
                            ["properties": ["type": ["const": "array"]], "required": ["type"]],
                            [
                              "properties": ["type": ["type": ["array"], "contains": ["const": "array"]]],
                              "required": ["type"],
                            ],
                            ["not": ["required": ["type"]]],
                          ]
                        ],
                        "then": [
                          "properties": [
                            "prefixItems": [
                              "type": ["array"],
                              "minItems": 2,
                              "maxItems": 2,
                              "prefixItems": [
                                ["$ref": "#/$defs/LocalTimeNumericItemSchema"],
                                ["$ref": "#/$defs/ZoneIdItemSchema"],
                              ],
                              "items": false,
                              "default": [
                                ["format": "local-time", "type": "integer", "units": "nanoseconds"],
                                ["type": "string", "format": "iana-time-zone"],
                              ],
                            ],
                            "minItems": ["default": 2],
                            "maxItems": ["default": 2],
                            "items": ["default": false],
                          ]
                        ],
                      ]
                    ],
                  ],
                ],

                // zoned-date-time
                [
                  "if": ["properties": ["format": ["const": "zoned-date-time"]], "required": ["format"]],
                  "then": [
                    "anyOf": [
                      ["properties": ["type": ["const": "string"]], "required": ["type"]],
                      ["properties": ["type": ["const": "array"]], "required": ["type"]],
                      [
                        "properties": ["type": ["type": ["array"], "contains": ["enum": ["string", "array"]]]],
                        "required": ["type"],
                      ],
                      ["not": ["required": ["type"]]],
                    ],
                    "properties": [
                      "units": ["default": "nanoseconds"]
                    ],
                    "allOf": [
                      [
                        "if": [
                          "anyOf": [
                            ["properties": ["type": ["const": "array"]], "required": ["type"]],
                            [
                              "properties": ["type": ["type": ["array"], "contains": ["const": "array"]]],
                              "required": ["type"],
                            ],
                            ["not": ["required": ["type"]]],
                          ]
                        ],
                        "then": [
                          "properties": [
                            "prefixItems": [
                              "type": ["array"],
                              "minItems": 2,
                              "maxItems": 2,
                              "prefixItems": [
                                ["$ref": "#/$defs/InstantNumericItemSchema"],
                                ["$ref": "#/$defs/ZoneIdItemSchema"],
                              ],
                              "items": false,
                              "default": [
                                ["format": "instant", "type": "integer", "units": "nanoseconds"],
                                ["type": "string", "format": "iana-time-zone"],
                              ],
                            ],
                            "minItems": ["default": 2],
                            "maxItems": ["default": 2],
                            "items": ["default": false],
                          ]
                        ],
                      ]
                    ],
                  ],
                ],

                // interval (time interval / duration-like)
                [
                  "if": ["properties": ["format": ["const": "interval"]], "required": ["format"]],
                  "then": [
                    "anyOf": [
                      ["properties": ["type": ["const": "string"]], "required": ["type"]],
                      ["properties": ["type": ["const": "number"]], "required": ["type"]],
                      ["properties": ["type": ["const": "integer"]], "required": ["type"]],
                      [
                        "properties": [
                          "type": ["type": ["array"], "contains": ["enum": ["string", "number", "integer"]]]
                        ], "required": ["type"],
                      ],
                      ["not": ["required": ["type"]]],
                    ],
                    "properties": ["units": ["default": "nanoseconds"]],
                  ],
                ],

                // period (calendar period)
                [
                  "if": ["properties": ["format": ["const": "period"]], "required": ["format"]],
                  "then": [
                    "anyOf": [
                      ["properties": ["type": ["const": "string"]], "required": ["type"]],
                      ["properties": ["type": ["const": "object"]], "required": ["type"]],
                      [
                        "properties": ["type": ["type": ["array"], "contains": ["enum": ["string", "object"]]]],
                        "required": ["type"],
                      ],
                      ["not": ["required": ["type"]]],
                    ]
                  ],
                ],

                // duration (calendar+time duration)
                [
                  "if": ["properties": ["format": ["const": "duration"]], "required": ["format"]],
                  "then": [
                    "anyOf": [
                      ["properties": ["type": ["const": "string"]], "required": ["type"]],
                      ["properties": ["type": ["const": "object"]], "required": ["type"]],
                      [
                        "properties": ["type": ["type": ["array"], "contains": ["enum": ["string", "object"]]]],
                        "required": ["type"],
                      ],
                      ["not": ["required": ["type"]]],
                    ]
                  ],
                ],
              ],
            ],

            "UUIDSpec": [
              "description": """
                UUID in Solid Schema.
              
                Allowed schema shapes:
                  - type: string, format: uuid (contentEncoding optional)
                  - type: bytes,  format: uuid (must be exactly 16 bytes)
              """,
              "type": ["object"],
              "additionalProperties": true,
              "properties": [
                "format": ["const": "uuid"]
              ],
              "required": ["format"],
              "allOf": [
                [
                  "anyOf": [
                    // string form
                    [
                      "properties": [
                        "type": ["const": "string"],
                        "contentEncoding": ["default": "uuid-canonical"],
                      ]
                    ],
                    [
                      "properties": [
                        "type": [
                          "type": ["array"],
                          "contains": ["const": "string"],
                        ],
                        "contentEncoding": ["default": "uuid-canonical"],
                      ]
                    ],

                    // bytes form (enforce 16 bytes)
                    [
                      "properties": [
                        "type": ["const": "bytes"],
                        "minSize": ["const": 16, "default": 16],
                        "maxSize": ["const": 16, "default": 16],
                      ],
                    ],
                    [
                      "properties": [
                        "type": [
                          "type": ["array"],
                          "contains": ["const": "bytes"],
                        ],
                        "minSize": ["const": 16, "default": 16],
                        "maxSize": ["const": 16, "default": 16],
                      ],
                    ],

                    // omitted type (freeform schemas) — allow, but still provide helpful defaults
                    [
                      "not": ["required": ["type"]],
                      "properties": [
                        "contentEncoding": ["default": "uuid-canonical"],
                        "minSize": ["default": 16],
                        "maxSize": ["default": 16],
                      ],
                    ],
                  ]
                ]
              ],
            ],

            "NetworkAndTextSpec": [
              "description": "Standard JSON-Schema-ish formats (strings) + Solid `bytes` allowance for some.",
              "type": ["object"],
              "additionalProperties": true,
              "allOf": [
                // URI / pointers / regex / email / hostnames are string-only
                [
                  "if": [
                    "properties": [
                      "format": [
                        "enum": [
                          "uri", "uri-reference", "iri", "iri-reference", "uri-template",
                          "json-pointer", "relative-json-pointer",
                          "regex",
                          "email", "idn-email",
                          "hostname", "idn-hostname",
                        ]
                      ]
                    ], "required": ["format"],
                  ],
                  "then": [
                    "anyOf": [
                      ["properties": ["type": ["const": "string"]], "required": ["type"]],
                      [
                        "properties": ["type": ["type": ["array"], "contains": ["const": "string"]]],
                        "required": ["type"],
                      ],
                      ["not": ["required": ["type"]]],
                    ]
                  ],
                ],

                // IP can be string or bytes in Solid
                [
                  "if": ["properties": ["format": ["enum": ["ipv4", "ipv6"]]], "required": ["format"]],
                  "then": [
                    "allOf": [
                      // Allow string or bytes (or omitted type)
                      [
                        "anyOf": [
                          ["properties": ["type": ["const": "string"]], "required": ["type"]],
                          ["properties": ["type": ["const": "bytes"]], "required": ["type"]],
                          [
                            "properties": [
                              "type": [
                                "type": ["array"],
                                "contains": ["enum": ["string", "bytes"]],
                              ]
                            ],
                            "required": ["type"],
                          ],
                          ["not": ["required": ["type"]]],
                        ]
                      ],

                      // If bytes are allowed/used, constrain sizes based on ipv4 vs ipv6
                      [
                        "if": [
                          "allOf": [
                            [
                              "anyOf": [
                                ["properties": ["type": ["const": "bytes"]], "required": ["type"]],
                                [
                                  "properties": [
                                    "type": [
                                      "type": ["array"],
                                      "contains": ["const": "bytes"],
                                    ]
                                  ],
                                  "required": ["type"],
                                ],
                              ]
                            ],
                            ["properties": ["format": ["const": "ipv4"]], "required": ["format"]],
                          ]
                        ],
                        "then": [
                          "properties": [
                            "minSize": ["const": 4, "default": 4],
                            "maxSize": ["const": 4, "default": 4],
                          ],
                        ],
                      ],
                      [
                        "if": [
                          "allOf": [
                            [
                              "anyOf": [
                                ["properties": ["type": ["const": "bytes"]], "required": ["type"]],
                                [
                                  "properties": [
                                    "type": [
                                      "type": ["array"],
                                      "contains": ["const": "bytes"],
                                    ]
                                  ],
                                  "required": ["type"],
                                ],
                              ]
                            ],
                            ["properties": ["format": ["const": "ipv6"]], "required": ["format"]],
                          ]
                        ],
                        "then": [
                          "properties": [
                            "minSize": ["const": 16, "default": 16],
                            "maxSize": ["const": 16, "default": 16],
                          ],
                        ],
                      ],
                    ]
                  ],
                ],
              ],
            ],
          ],
        ],
        options: options
      )

      private static let options = Schema.Options(
        defaultSchema: .v1_2020_12_Solid,
        unknownKeywords: .annotate,
        schemaLocator: LocalSchemaContainer.empty,
        metaSchemaLocator: Solid_v1_2020_12.instance,
        vocabularyLocator: Solid_v1_2020_12.Vocabularies.instance,
        formatTypeLocator: FormatTypes(),
        contentMediaTypeLocator: ContentMediaTypeTypes(),
        contentEncodingLocator: ContentEncodingTypes(),
        collectAnnotations: .none
      )
    }
  }
}

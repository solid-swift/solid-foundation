//
//  Schema-Options.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/9/25.
//

import SolidData
import SolidURI


extension Schema {

  public struct Options {

    public static let defaultMetaSchemaLocators: [MetaSchemaLocator] = [
      MetaSchema.Draft2020_12.instance
    ]

    public static let defaultVocabularyLocators: [VocabularyLocator] = [
      MetaSchema.Draft2020_12.Vocabularies.instance
    ]

    public static let `default`: Self = {
      let schemaLocator = CompositeSchemaLocator.from(locators: [])
      let metaSchemaLocator = CompositeMetaSchemaLocator(locators: defaultMetaSchemaLocators)
      let vocabularyLocator = CompositeVocabularyLocator(locators: defaultVocabularyLocators)
      return Self(
        defaultSchema: .v2020_12,
        unknownKeywords: .annotate,
        schemaLocator: schemaLocator,
        metaSchemaLocator: metaSchemaLocator,
        vocabularyLocator: LocalVocabularyContainer(vocabularyLocator: vocabularyLocator),
        formatTypeLocator: FormatTypes(),
        contentMediaTypeLocator: ContentMediaTypeTypes(),
        contentEncodingLocator: ContentEncodingTypes(),
        collectAnnotations: .none,
        trace: false
      )
    }()

    public static func `default`(for defaultSchema: MetaSchema) -> Self { .default.defaultSchema(defaultSchema) }

    public enum CollectAnnotations {

      public enum Filter {
        case keywords([Keyword])
      }

      case none
      case all
      case matching(Filter)
    }

    public enum UnknownKeywords {
      case annotate
      case ignore
      case fail
      case custom(@Sendable (Keyword, Value, Pointer) throws -> KeywordBehavior?)
    }

    public let defaultResourceId: URI = URI(valid: "https://example.com/schema")
    public let defaultSchema: MetaSchema
    public let unknownKeywords: UnknownKeywords
    public let schemaLocator: SchemaLocator
    public let metaSchemaLocator: MetaSchemaLocator
    public let vocabularyLocator: VocabularyLocator
    public let formatTypeLocator: FormatTypeLocator
    public let contentMediaTypeLocator: ContentMediaTypeLocator
    public let contentEncodingLocator: ContentEncodingLocator
    public let collectAnnotations: CollectAnnotations
    public let formatModeOverride: Schema.Strings.Format.Mode?
    public let trace: Bool

    public init(
      defaultSchema: MetaSchema,
      unknownKeywords: UnknownKeywords,
      schemaLocator: SchemaLocator,
      metaSchemaLocator: MetaSchemaLocator,
      vocabularyLocator: VocabularyLocator,
      formatTypeLocator: FormatTypeLocator,
      contentMediaTypeLocator: ContentMediaTypeLocator,
      contentEncodingLocator: ContentEncodingLocator,
      collectAnnotations: CollectAnnotations,
      formatModeOverride: Schema.Strings.Format.Mode? = nil,
      trace: Bool = false,
    ) {
      self.defaultSchema = defaultSchema
      self.unknownKeywords = unknownKeywords
      self.schemaLocator = schemaLocator
      self.metaSchemaLocator = metaSchemaLocator
      self.vocabularyLocator = vocabularyLocator
      self.formatTypeLocator = formatTypeLocator
      self.contentMediaTypeLocator = contentMediaTypeLocator
      self.contentEncodingLocator = contentEncodingLocator
      self.collectAnnotations = collectAnnotations
      self.formatModeOverride = formatModeOverride
      self.trace = trace
    }

    private func copy(
      defaultSchema: MetaSchema? = nil,
      unknownKeywords: UnknownKeywords? = nil,
      schemaLocator: SchemaLocator? = nil,
      metaSchemaLocator: MetaSchemaLocator? = nil,
      vocabularyLocator: VocabularyLocator? = nil,
      formatTypeLocator: FormatTypeLocator? = nil,
      contentMediaTypeLocator: ContentMediaTypeLocator? = nil,
      contentEncodingLocator: ContentEncodingLocator? = nil,
      collectAnnotations: CollectAnnotations? = nil,
      formatModeOverride: Schema.Strings.Format.Mode? = nil,
      trace: Bool? = nil,
    ) -> Self {
      Self(
        defaultSchema: defaultSchema ?? self.defaultSchema,
        unknownKeywords: unknownKeywords ?? self.unknownKeywords,
        schemaLocator: schemaLocator ?? self.schemaLocator,
        metaSchemaLocator: metaSchemaLocator ?? self.metaSchemaLocator,
        vocabularyLocator: vocabularyLocator ?? self.vocabularyLocator,
        formatTypeLocator: formatTypeLocator ?? self.formatTypeLocator,
        contentMediaTypeLocator: contentMediaTypeLocator ?? self.contentMediaTypeLocator,
        contentEncodingLocator: contentEncodingLocator ?? self.contentEncodingLocator,
        collectAnnotations: collectAnnotations ?? self.collectAnnotations,
        formatModeOverride: formatModeOverride ?? self.formatModeOverride,
        trace: trace ?? self.trace,
      )
    }

    public func defaultSchema(_ value: MetaSchema) -> Self {
      copy(defaultSchema: value)
    }

    public func schemaLocator(_ value: SchemaLocator) -> Self {
      copy(schemaLocator: value)
    }

    public func metaSchemaLocator(_ value: MetaSchemaLocator) -> Self {
      copy(metaSchemaLocator: value)
    }

    public func formatTypeLocator(_ value: FormatTypeLocator) -> Self {
      copy(formatTypeLocator: value)
    }

    public func contentTypeLocator(_ value: ContentMediaTypeLocator) -> Self {
      copy(contentMediaTypeLocator: value)
    }

    public func unknownKeywords(_ value: UnknownKeywords) -> Self {
      copy(unknownKeywords: value)
    }

    public func ignoreUnknownKeywords() -> Self {
      copy(unknownKeywords: .ignore)
    }

    public func failOnUnknownKeywords() -> Self {
      copy(unknownKeywords: .fail)
    }

    public func customUnknownKeywords(
      handler: @Sendable @escaping (Keyword, Value, Pointer) throws -> KeywordBehavior?
    ) -> Self {
      copy(unknownKeywords: .custom(handler))
    }

    public func collectAnnotations(_ value: CollectAnnotations = .all) -> Self {
      copy(collectAnnotations: value)
    }

    public func formatModeOverride(_ mode: Schema.Strings.Format.Mode) -> Self {
      copy(formatModeOverride: mode)
    }

    public func trace(_ value: Bool = true) -> Self {
      copy(trace: value)
    }

  }

}

extension Schema.Options: Sendable {}

extension Schema.Options.CollectAnnotations.Filter: Sendable {}
extension Schema.Options.CollectAnnotations.Filter: Hashable {}
extension Schema.Options.CollectAnnotations.Filter: Equatable {}

extension Schema.Options.CollectAnnotations: Sendable {}
extension Schema.Options.CollectAnnotations: Hashable {}
extension Schema.Options.CollectAnnotations: Equatable {}

extension Schema.Options.UnknownKeywords: Sendable {}

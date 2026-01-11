//
//  MetaSchema-Vocabulary.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/9/25.
//

import SolidURI
import OrderedCollections


extension MetaSchema {

  public struct Vocabulary {

    public let id: URI
    public let types: OrderedSet<Schema.InstanceType>
    public let keywordBehaviors: OrderedDictionary<Keyword, any Schema.KeywordBehaviorBuilder.Type>

    public init(
      id: URI,
      types: OrderedSet<Schema.InstanceType> = [],
      keywordBehaviors: [any Schema.KeywordBehaviorBuilder.Type] = []
    ) {
      self.id = id
      self.types = types
      self.keywordBehaviors = keywordBehaviors.reduce(into: [:]) { $0[$1.keyword] = $1 }
    }

  }

}

extension MetaSchema.Vocabulary: Sendable {}

extension MetaSchema.Vocabulary: Hashable {

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

}

extension MetaSchema.Vocabulary: Equatable {

  public static func == (lhs: MetaSchema.Vocabulary, rhs: MetaSchema.Vocabulary) -> Bool {
    lhs.id == rhs.id
  }

}

extension MetaSchema.Vocabulary: VocabularyLocator {

  public func locate(vocabularyId id: URI, options: Schema.Options) throws -> MetaSchema.Vocabulary? {
    guard id == self.id else { return nil }
    return self
  }

}

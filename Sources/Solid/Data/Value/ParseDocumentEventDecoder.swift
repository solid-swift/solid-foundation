//
//  ParseDocumentEventDecoder.swift
//  SolidFoundation
//
//  Created by Codex on 4/27/26.
//

/// A decoded value document with format-neutral boundary metadata.
public struct FormatValueDocument: Sendable, Equatable {
  public var value: Value
  public var explicitStart: Bool
  public var explicitEnd: Bool

  public init(value: Value, explicitStart: Bool = false, explicitEnd: Bool = false) {
    self.value = value
    self.explicitStart = explicitStart
    self.explicitEnd = explicitEnd
  }
}

/// Decodes document-framed parse events into value documents.
public struct ParseDocumentEventDecoder {

  public enum Error: Swift.Error {
    case invalidEventSequence(String)
    case incompleteDocument
  }

  private let resolver: any ScalarResolver
  private var decoder: ParseEventDecoder?
  private var explicitStart = false

  public init(resolver: any ScalarResolver) {
    self.resolver = resolver
  }

  public mutating func append(_ event: ParseDocumentEvent) throws -> FormatValueDocument? {
    switch event {
    case .startDocument(let metadata):
      guard decoder == nil else {
        throw Error.invalidEventSequence("Document started before previous document ended")
      }
      decoder = ParseEventDecoder(resolver: resolver)
      explicitStart = metadata.explicit
      return nil

    case .event(let parseEvent):
      if decoder == nil {
        decoder = ParseEventDecoder(resolver: resolver)
        explicitStart = false
      }
      try decoder?.append(parseEvent)
      return nil

    case .endDocument(let metadata):
      guard var current = decoder else {
        throw Error.invalidEventSequence("Document ended before it started")
      }
      guard current.isComplete else {
        throw Error.incompleteDocument
      }
      let value = try current.finish()
      decoder = nil
      defer { explicitStart = false }
      return FormatValueDocument(
        value: value,
        explicitStart: explicitStart,
        explicitEnd: metadata.explicit
      )
    }
  }

  public func finish() throws {
    if decoder != nil {
      throw Error.incompleteDocument
    }
  }
}

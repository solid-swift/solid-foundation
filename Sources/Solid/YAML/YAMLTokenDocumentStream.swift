//
//  YAMLTokenDocumentStream.swift
//  SolidFoundation
//
//  Created by Codex on 4/25/26.
//

import Foundation
import SolidData

struct YAMLTokenDocument: Sendable {
  var events: [ParseEvent]
  var explicitStart: Bool
  var explicitEnd: Bool
}

struct YAMLTokenDocumentStream: ~Copyable, @unchecked Sendable {

  private var tokenizer = YAMLTokenizer()
  private var adapter = YAMLTokenEventAdapter()
  private var bufferedEvents: [ParseEvent] = []
  private var bufferIndex = 0
  private var finalReceived = false
  private var finished = false
  private var eventDocumentOpen = false
  private var eventDocumentHasContent = false
  private var documentEvents: [ParseEvent] = []
  private var documentExplicitStart = false
  private var documentSawStart = false
  private var documentEventSawStart = false
  private var documentEventHasContent = false
  private var pendingDocumentEventEnd: FormatDocumentMetadata?

  var isFinished: Bool { finished }

  mutating func feedInput(_ data: consuming Data, isFinal: Bool) {
    tokenizer.feedInput(data, isFinal: isFinal)
    if isFinal {
      finalReceived = true
    }
  }

  mutating func readEvent() throws -> ParseEvent? {
    guard !finished else { return nil }

    if bufferIndex < bufferedEvents.count {
      let event = bufferedEvents[bufferIndex]
      bufferIndex += 1
      if bufferIndex == bufferedEvents.count {
        bufferedEvents.removeAll(keepingCapacity: true)
        bufferIndex = 0
      }
      return event
    }

    while bufferedEvents.isEmpty {
      guard let token = try tokenizer.readToken() else {
        if finalReceived {
          finished = true
        }
        return nil
      }
      switch token {
      case .directive:
        continue

      case .documentStart:
        eventDocumentOpen = true
        eventDocumentHasContent = false

      case .documentEnd:
        if eventDocumentOpen, !eventDocumentHasContent {
          Self.appendEmptyDocumentEvents(into: &bufferedEvents)
          eventDocumentHasContent = true
        }
        eventDocumentOpen = false

      default:
        if !eventDocumentOpen {
          eventDocumentOpen = true
          eventDocumentHasContent = false
        }
        let startCount = bufferedEvents.count
        try adapter.append(token, into: &bufferedEvents)
        if bufferedEvents.count > startCount {
          eventDocumentHasContent = true
        }
      }
    }

    return try readEvent()
  }

  mutating func readDocument() throws -> YAMLTokenDocument? {
    guard !finished else { return nil }

    while true {
      guard let token = try tokenizer.readToken() else {
        if finalReceived {
          finished = true
        }
        return nil
      }

      switch token {
      case .directive:
        continue

      case .documentStart(let explicit):
        documentSawStart = true
        documentExplicitStart = explicit

      case .documentEnd(let explicit):
        guard documentSawStart else {
          continue
        }
        if documentEvents.isEmpty {
          Self.appendEmptyDocumentEvents(into: &documentEvents)
        }
        let document = YAMLTokenDocument(
          events: documentEvents,
          explicitStart: documentExplicitStart,
          explicitEnd: explicit
        )
        documentEvents.removeAll(keepingCapacity: true)
        documentExplicitStart = false
        documentSawStart = false
        return document

      default:
        documentSawStart = true
        try adapter.append(token, into: &documentEvents)
      }
    }
  }

  mutating func readDocumentEvent() throws -> ParseDocumentEvent? {
    guard !finished else { return nil }

    if let event = readBufferedDocumentEvent() {
      return event
    }

    while true {
      guard let token = try tokenizer.readToken() else {
        if finalReceived {
          finished = true
        }
        return nil
      }

      switch token {
      case .directive:
        continue

      case .documentStart(let explicit):
        documentEventSawStart = true
        documentEventHasContent = false
        return .startDocument(.init(explicit: explicit))

      case .documentEnd(let explicit):
        guard documentEventSawStart else {
          continue
        }
        if !documentEventHasContent {
          Self.appendEmptyDocumentEvents(into: &bufferedEvents)
          documentEventHasContent = true
          pendingDocumentEventEnd = .init(explicit: explicit)
          return readBufferedDocumentEvent()
        }
        documentEventSawStart = false
        documentEventHasContent = false
        return .endDocument(.init(explicit: explicit))

      default:
        if !documentEventSawStart {
          documentEventSawStart = true
          documentEventHasContent = false
          pendingDocumentEventEnd = nil
          let startCount = bufferedEvents.count
          try adapter.append(token, into: &bufferedEvents)
          if bufferedEvents.count > startCount {
            documentEventHasContent = true
          }
          return .startDocument(.implicit)
        }
        let startCount = bufferedEvents.count
        try adapter.append(token, into: &bufferedEvents)
        if bufferedEvents.count > startCount {
          documentEventHasContent = true
        }
        if let event = readBufferedDocumentEvent() {
          return event
        }
      }
    }
  }

  mutating func readValueDocument() throws -> YAMLValueDocument? {
    guard let document = try readDocument() else {
      return nil
    }

    var decoder = ParseDocumentEventDecoder(resolver: YAMLScalarResolver())
    _ = try decoder.append(.startDocument(.init(explicit: document.explicitStart)))
    for event in document.events {
      _ = try decoder.append(.event(event))
    }
    guard let valueDocument = try decoder.append(.endDocument(.init(explicit: document.explicitEnd))) else {
      throw YAML.ParseError.incompleteInput(location: nil)
    }
    return YAMLValueDocument(
      value: valueDocument.value,
      explicitStart: valueDocument.explicitStart,
      explicitEnd: valueDocument.explicitEnd
    )
  }

  mutating func readNodeDocument() throws -> YAMLDocument? {
    guard !finished else { return nil }

    var builder = YAMLRawTokenNodeBuilder()
    var explicitStart = false
    var sawDocument = false

    while true {
      guard let token = try tokenizer.readToken() else {
        if finalReceived {
          finished = true
        }
        return nil
      }

      switch token {
      case .directive:
        continue

      case .documentStart(let explicit):
        builder = YAMLRawTokenNodeBuilder()
        explicitStart = explicit
        sawDocument = true

      case .documentEnd(let explicit):
        guard sawDocument else {
          continue
        }
        return YAMLDocument(
          node: try builder.finish(),
          explicitStart: explicitStart,
          explicitEnd: explicit
        )

      default:
        sawDocument = true
        try builder.append(token)
      }
    }
  }

  private static func appendEmptyDocumentEvents(into events: inout [ParseEvent]) {
    events.append(.style(.scalar(.plain)))
    events.append(.scalar(.materialized(.string(""))))
  }

  private mutating func readBufferedDocumentEvent() -> ParseDocumentEvent? {
    if bufferIndex < bufferedEvents.count {
      let event = bufferedEvents[bufferIndex]
      bufferIndex += 1
      if bufferIndex == bufferedEvents.count {
        bufferedEvents.removeAll(keepingCapacity: true)
        bufferIndex = 0
      }
      return .event(event)
    }
    if let metadata = pendingDocumentEventEnd {
      pendingDocumentEventEnd = nil
      documentEventSawStart = false
      documentEventHasContent = false
      return .endDocument(metadata)
    }
    return nil
  }
}

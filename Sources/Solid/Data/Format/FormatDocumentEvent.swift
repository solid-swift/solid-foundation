//
//  FormatDocumentEvent.swift
//  SolidFoundation
//
//  Created by Codex on 4/27/26.
//

import Foundation

/// Metadata attached to document boundary events.
///
/// Formats with explicit document markers, such as YAML, set ``explicit`` to
/// preserve whether the boundary came from the source. Formats without native
/// markers use the implicit default.
public struct FormatDocumentMetadata: Sendable, Equatable {
  public var explicit: Bool

  public init(explicit: Bool = false) {
    self.explicit = explicit
  }

  public static let implicit = FormatDocumentMetadata()
}

/// A document-framed event stream.
///
/// The wrapped `Event` remains a value-level event, such as ``ParseEvent`` or
/// ``EmitEvent``. Document boundaries live in this outer layer so value-level
/// decoders and encoders do not need to handle stream framing.
public enum FormatDocumentEvent<Event: Sendable>: Sendable {
  case startDocument(FormatDocumentMetadata)
  case event(Event)
  case endDocument(FormatDocumentMetadata)
}

extension FormatDocumentEvent: Equatable where Event: Equatable {}

public typealias ParseDocumentEvent = FormatDocumentEvent<ParseEvent>
public typealias EmitDocumentEvent = FormatDocumentEvent<EmitEvent>

/// Small FIFO for events produced ahead of caller output capacity.
package struct PendingEventQueue<Event: Sendable>: Sendable {
  private var events: [Event] = []
  private var index = 0

  package init() {}

  package mutating func append(_ event: consuming Event) {
    events.append(event)
  }

  @discardableResult
  package mutating func drain(into output: inout OutputSpan<Event>) -> Bool {
    var produced = false
    while index < events.count, !output.isFull {
      output.append(events[index])
      index += 1
      produced = true
    }
    if index == events.count {
      events.removeAll(keepingCapacity: true)
      index = 0
    }
    return produced
  }
}

/// Structurally frames a value-level parse event stream into documents.
///
/// This does not materialize scalars. It treats every root value as one
/// document, which gives JSON a single synthetic document and CBOR one document
/// per root value.
public struct ParseEventDocumentFramer: Sendable {

  public enum Error: Swift.Error, Sendable {
    case incompleteDocument
    case unbalancedContainer
  }

  private var documentOpen = false
  private var depth = 0

  public init() {}

  public var hasOpenDocument: Bool { documentOpen }

  public mutating func append(
    _ event: ParseEvent,
    into output: inout [ParseDocumentEvent]
  ) throws {
    try append(event) { output.append($0) }
  }

  package mutating func append(
    _ event: ParseEvent,
    into output: inout PendingEventQueue<ParseDocumentEvent>
  ) throws {
    try append(event) { output.append($0) }
  }

  private mutating func append(
    _ event: ParseEvent,
    emit: (ParseDocumentEvent) throws -> Void
  ) throws {
    if !documentOpen {
      try emit(.startDocument(.implicit))
      documentOpen = true
    }

    try emit(.event(event))

    switch event {
    case .style, .tag, .anchor:
      return

    case .alias, .scalar:
      if depth == 0 {
        try finishDocument(emit: emit)
      }

    case .beginArray, .beginObject:
      depth += 1

    case .endArray, .endObject:
      depth -= 1
      guard depth >= 0 else {
        throw Error.unbalancedContainer
      }
      if depth == 0 {
        try finishDocument(emit: emit)
      }
    }
  }

  public func finish() throws {
    if documentOpen {
      throw Error.incompleteDocument
    }
  }

  private mutating func finishDocument(
    emit: (ParseDocumentEvent) throws -> Void
  ) throws {
    try emit(.endDocument(.implicit))
    documentOpen = false
  }
}

/// Adapts a value-level ``FormatStreamReader`` into a document-framed stream.
public struct DocumentFramedStreamReader<Reader: ~Copyable & FormatStreamReader>: ~Copyable, FormatDocumentStreamReader {

  public var reader: Reader

  private var framer = ParseEventDocumentFramer()
  private var pendingEvents = PendingEventQueue<ParseDocumentEvent>()

  public init(reader: consuming Reader) {
    self.reader = reader
  }

  public var format: Format { reader.format }

  public mutating func read(
    input: Data,
    isFinal: Bool,
    output: inout OutputSpan<ParseDocumentEvent>
  ) throws -> FormatStreamReadStatus {
    var produced = pendingEvents.drain(into: &output)
    if output.isFull {
      return .producedOutput
    }

    var inputToRead = input
    var finalToRead = isFinal

    while !output.isFull {
      var readerStatus = FormatStreamReadStatus.needMoreInput
      try withUnsafeTemporaryAllocation(of: ParseEvent.self, capacity: 64) { buffer in
        var out = OutputSpan<ParseEvent>(buffer: buffer, initializedCount: 0)
        readerStatus = try reader.read(input: inputToRead, isFinal: finalToRead, output: &out)
        inputToRead = Data()
        finalToRead = false

        let count = out.finalize(for: buffer)
        if count > 0 {
          for event in buffer[..<count] {
            try framer.append(event, into: &pendingEvents)
          }
        }
      }

      produced = pendingEvents.drain(into: &output) || produced
      if output.isFull {
        return .producedOutput
      }

      switch readerStatus {
      case .producedOutput:
        continue
      case .needMoreInput:
        return produced ? .producedOutput : .needMoreInput
      case .endOfStream:
        try framer.finish()
        return produced ? .producedOutput : .endOfStream
      }
    }

    return produced ? .producedOutput : .needMoreInput
  }
}

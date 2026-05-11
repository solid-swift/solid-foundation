//
//  YAMLStreamReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData

/// Synchronous YAML stream reader that produces ``ParseEvent`` values.
///
/// Built on ``BufferedStreamDecoder`` wrapping a ``YAMLEventReader``.
public typealias YAMLStreamReader = BufferedStreamDecoder<YAMLEventReader>

extension BufferedStreamDecoder where Reader == YAMLEventReader {

  public init() {
    self.init(reader: YAMLEventReader())
  }
}

/// YAML document-framed event reader.
///
/// Unlike the value-level ``YAMLStreamReader``, this reader preserves explicit
/// document boundary metadata from `---` and `...` markers.
public struct YAMLDocumentEventReader: ~Copyable, FormatDocumentStreamReader {

  private var stream = YAMLTokenDocumentStream()
  private var pendingEvents = PendingEventQueue<ParseDocumentEvent>()

  public init() {}

  public var format: Format { YAML.format }

  public mutating func read(
    input: Data,
    isFinal: Bool,
    output: inout OutputSpan<ParseDocumentEvent>
  ) throws -> FormatStreamReadStatus {
    stream.feedInput(input, isFinal: isFinal)

    var produced = pendingEvents.drain(into: &output)
    if output.isFull {
      return .producedOutput
    }

    while !output.isFull {
      guard let event = try stream.readDocumentEvent() else {
        if stream.isFinished {
          return produced ? .producedOutput : .endOfStream
        }
        return produced ? .producedOutput : .needMoreInput
      }

      pendingEvents.append(event)
      produced = pendingEvents.drain(into: &output) || produced
    }

    return produced ? .producedOutput : .needMoreInput
  }
}

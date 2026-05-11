//
//  BufferedStreamDecoder.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 3/21/26.
//

import Foundation

/// A generic ``FormatStreamReader`` that wraps a ``FormatEventReader``,
/// adapting its push-parser interface to the streaming reader protocol.
///
/// Mirrors ``BufferedStreamEncoder`` on the writing side. Each format-specific
/// parser becomes a ``FormatEventReader`` that owns only its parsing state.
/// `BufferedStreamDecoder` handles the `read` lifecycle, feeding input and
/// pulling events without materialization.
public struct BufferedStreamDecoder<Reader: ~Copyable & FormatEventReader>: ~Copyable, FormatStreamReader {

  public var reader: Reader

  public init(reader: consuming Reader) {
    self.reader = reader
  }

  public var format: Format { reader.format }

  public mutating func read(
    input: Data,
    isFinal: Bool,
    output: inout OutputSpan<ParseEvent>
  ) throws -> FormatStreamReadStatus {
    if !input.isEmpty || isFinal {
      reader.feedInput(input, isFinal: isFinal)
    }

    var produced = false
    while !output.isFull {
      guard let event = try reader.readEvent() else {
        if reader.isFinished {
          return produced ? .producedOutput : .endOfStream
        }
        return produced ? .producedOutput : .needMoreInput
      }
      output.append(event)
      produced = true
    }

    return .producedOutput
  }
}

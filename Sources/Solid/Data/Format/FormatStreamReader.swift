//
//  FormatStreamReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import Foundation

/// Status returned from a streaming read operation.
public enum FormatStreamReadStatus: Sendable, Equatable {
  /// Produced output events (or filled the output span).
  case producedOutput
  /// Needs more input to make progress.
  case needMoreInput
  /// End of stream reached.
  case endOfStream
}

/// Streaming reader for a ``Format``.
public protocol FormatStreamReader: ~Copyable {

  /// The format this reader reads.
  var format: Format { get }

  /// Read events from the provided input buffer.
  ///
  /// - Parameters:
  ///   - input: Input data buffer.
  ///   - output: Output span for emitted events.
  /// - Returns: Status indicating progress or completion.
  /// - Throws: Error if the input cannot be parsed.
  mutating func read(
    input: Data,
    isFinal: Bool,
    output: inout OutputSpan<ParseEvent>
  ) throws -> FormatStreamReadStatus
}

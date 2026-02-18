//
//  FormatEventWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import Foundation

/// A synchronous event writer that serializes ``ValueEvent`` values into bytes.
///
/// Conformers own only their format-specific semantic state (containers, tags, style)
/// and write formatted bytes into a provided `inout Data` buffer. Buffer management
/// and the ``FormatStreamEncoder`` protocol are handled by ``BufferedStreamEncoder``.
public protocol FormatEventWriter {

  /// The format this writer produces.
  var format: Format { get }

  /// Write a single event's bytes into the buffer.
  mutating func writeEvent(_ event: ValueEvent, into buffer: inout Data) throws

  /// Validate completion state and write any finalization bytes (e.g., trailing newline)
  /// into the buffer.
  mutating func finishWriting(into buffer: inout Data) throws
}

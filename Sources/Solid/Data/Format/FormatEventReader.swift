//
//  FormatEventReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 3/21/26.
//

import Foundation

/// A synchronous push parser that reads format-specific bytes and produces ``ParseEvent`` values.
///
/// Mirrors ``FormatEventWriter`` on the writing side. Conformers own their format-specific
/// parsing state (tokenizer, container tracking) and produce events from incrementally
/// provided input data.
///
/// Buffer management and the ``FormatStreamReader`` protocol are handled by
/// ``BufferedStreamDecoder``.
public protocol FormatEventReader: ~Copyable {

  /// The format this reader parses.
  var format: Format { get }

  /// The scalar resolver for materializing ``ScalarRef`` values produced by this reader.
  var scalarResolver: any ScalarResolver { get }

  /// Feed input data to the reader.
  ///
  /// - Parameters:
  ///   - data: New input bytes to process.
  ///   - isFinal: Whether this is the last chunk of input.
  mutating func feedInput(_ data: consuming Data, isFinal: Bool)

  /// Read the next event from buffered input.
  ///
  /// Returns `nil` when more input is needed to produce the next event.
  /// After ``isFinished`` becomes `true`, always returns `nil`.
  ///
  /// - Returns: The next parse event, or `nil` if more input is needed.
  /// - Throws: If the input contains invalid data for this format.
  mutating func readEvent() throws -> ParseEvent?

  /// Whether the reader has completed processing all input.
  var isFinished: Bool { get }
}

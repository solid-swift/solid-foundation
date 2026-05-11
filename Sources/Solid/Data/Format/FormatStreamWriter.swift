//
//  FormatStreamWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

/// Streaming writer for a ``Format``.
public protocol FormatStreamWriter {

  /// The format this writer writes.
  var format: Format { get }

  /// Write the next event.
  ///
  /// - Parameter event: The event to write.
  /// - Throws: Error if the event cannot be written.
  func write(_ event: EmitEvent) async throws

  /// Finish the stream, emitting any closing bytes.
  ///
  /// - Throws: Error if the stream cannot be finished.
  func finish() async throws

  /// Close the underlying sink.
  ///
  /// - Throws: Error if the sink cannot be closed.
  func close() async throws
}

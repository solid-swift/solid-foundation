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
  func write(_ event: ValueEvent) async throws
}

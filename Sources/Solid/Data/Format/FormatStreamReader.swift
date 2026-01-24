//
//  FormatStreamReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

/// Streaming reader for a ``Format``.
public protocol FormatStreamReader {

  /// The format this reader reads.
  var format: Format { get }

  /// Read the next available event.
  ///
  /// - Returns: The next event, or `nil` if the stream has ended.
  /// - Throws: Error if the next event cannot be read.
  func next() async throws -> ValueEvent?
}

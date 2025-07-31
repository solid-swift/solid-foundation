//
//  Stream.swift
//  SolidIO
//
//  Created by Kevin Wooten on 7/4/25.
//


/// Common stream protocol.
public protocol Stream: Sendable {

  /// Closes the stream.
  ///
  /// - Throws: ``IOError`` if stream finalization and/or close fails.
  func close() async throws

}

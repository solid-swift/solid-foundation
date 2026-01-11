//
//  FormatReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/10/26.
//


public protocol FormatReader {

  /// The format this writer writes.
  var format: Format { get }

  /// Read the next available value.
  ///
  /// - Returns: The next available value.
  /// - Throws: Error if a value cannot be read.
  ///
  func read() throws -> Value

}

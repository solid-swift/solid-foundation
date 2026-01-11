//
//  FormatWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/10/26.
//


public protocol FormatWriter {

  /// The format this writer writes.
  var format: Format { get }

  /// Write the value.
  ///
  /// - Parameter value: Value to write.
  /// - Throws: Error if the value cannot be written.
  ///
  func write(_ value: Value) throws

}

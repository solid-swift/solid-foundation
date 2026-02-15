//
//  FormatWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/10/26.
//

import Foundation

public protocol FormatWriter {

  /// The format this writer writes.
  var format: Format { get }

  /// Write the value and return the encoded bytes.
  ///
  /// - Parameter value: Value to write.
  /// - Returns: The encoded data.
  /// - Throws: Error if the value cannot be written.
  ///
  func write(_ value: Value) throws -> Data

}

//
//  JSONReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/25/25.
//

import SolidData
import Foundation

/// Synchronous JSON reader that loads into ``Value``.
public struct JSONValueReader: ~Copyable, FormatReader {

  private var reader: FormatValueReader<JSONStreamReader>

  public init(data: Data) {
    self.reader = FormatValueReader(
      reader: JSONStreamReader(reader: JSONEventReader()),
      data: data,
      format: JSON.format,
      scalarResolver: JSONScalarResolver(),
      unexpectedEndError: { JSON.Error.unexpectedEndOfStream },
      requiresEndOfStream: true,
      trailingDataError: {
        JSON.Error.invalidStructure("Extra data after root value")
      }
    )
  }

  public init(string: String) {
    self.init(data: Data(string.utf8))
  }

  public var format: Format { reader.format }

  public mutating func read() throws -> Value {
    try reader.read()
  }

  /// Validate that the data contains well-formed JSON without building a ``Value``.
  public mutating func validateValue() throws {
    _ = try reader.read()
  }
}

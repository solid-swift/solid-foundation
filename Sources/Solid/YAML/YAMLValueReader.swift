//
//  YAMLValueReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData
import SolidIO

/// Synchronous YAML reader that loads into ``Value``.
public struct YAMLValueReader: FormatReader {

  private var reader: FormatValueReader<YAMLStreamReader>

  public init(data: Data) throws {
    guard let text = String(data: data, encoding: .utf8) else {
      throw YAML.DataError.invalidEncoding(.utf8)
    }
    self.reader = FormatValueReader(
      reader: YAMLStreamReader(),
      data: Data(text.utf8),
      format: YAML.format,
      unexpectedEndError: {
        YAML.ParseError.invalidSyntax("Unexpected end of document", location: nil)
      }
    )
  }

  public init(string: String) {
    self.reader = FormatValueReader(
      reader: YAMLStreamReader(),
      data: Data(string.utf8),
      format: YAML.format,
      unexpectedEndError: {
        YAML.ParseError.invalidSyntax("Unexpected end of document", location: nil)
      }
    )
  }

  public var format: Format { reader.format }

  public mutating func read() throws -> Value {
    try reader.read()
  }
}

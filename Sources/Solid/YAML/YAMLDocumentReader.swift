//
//  YAMLDocumentReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData

/// Synchronous YAML reader that loads a full document stream.
public struct YAMLDocumentReader {

  private let data: Data

  public init(data: Data) throws {
    self.data = data
  }

  public init(string: String) {
    self.data = Data(string.utf8)
  }

  public func readAll() throws -> [YAMLValueDocument] {
    var reader = FormatDocumentValueReader(
      reader: YAMLDocumentEventReader(),
      data: data,
      resolver: YAMLScalarResolver(),
      unexpectedEndError: { YAML.ParseError.incompleteInput(location: nil) }
    )
    return try reader.readAll().map {
      YAMLValueDocument(
        value: $0.value,
        explicitStart: $0.explicitStart,
        explicitEnd: $0.explicitEnd
      )
    }
  }
}

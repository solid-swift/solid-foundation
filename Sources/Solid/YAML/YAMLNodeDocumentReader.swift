//
//  YAMLNodeDocumentReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation

/// Synchronous YAML reader that loads a full document stream as raw nodes.
struct YAMLNodeDocumentReader {

  private let data: Data

  init(data: Data) throws {
    self.data = data
  }

  init(string: String) {
    self.data = Data(string.utf8)
  }

  func readAll() throws -> [YAMLDocument] {
    var stream = YAMLTokenDocumentStream()
    stream.feedInput(data, isFinal: true)

    var documents: [YAMLDocument] = []
    while let document = try stream.readNodeDocument() {
      documents.append(document)
    }
    return documents
  }
}

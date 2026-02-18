//
//  YAMLNodeDocumentReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation

/// Synchronous YAML reader that loads a full document stream as raw nodes.
struct YAMLNodeDocumentReader {

  private let text: String

  init(data: Data) throws {
    guard let text = String(data: data, encoding: .utf8) else {
      throw YAML.DataError.invalidEncoding(.utf8)
    }
    self.text = text
  }

  init(string: String) {
    self.text = string
  }

  func readAll() throws -> [YAMLDocument] {
    var parser = try YAMLParser(text: text)
    return try parser.parseDocumentStream()
  }
}

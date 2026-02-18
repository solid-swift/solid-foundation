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

  private let text: String

  public init(data: Data) throws {
    guard let text = String(data: data, encoding: .utf8) else {
      throw YAML.DataError.invalidEncoding(.utf8)
    }
    self.text = text
  }

  public init(string: String) {
    self.text = string
  }

  public func readAll() throws -> [YAMLValueDocument] {
    var parser = try YAMLParser(text: text)
    let documents = try parser.parseDocumentStream()
    return try documents.map { doc in
      var anchors: [String: Value] = [:]
      let value = try doc.node.toValue(anchors: &anchors)
      return YAMLValueDocument(
        value: value,
        explicitStart: doc.explicitStart,
        explicitEnd: doc.explicitEnd
      )
    }
  }
}

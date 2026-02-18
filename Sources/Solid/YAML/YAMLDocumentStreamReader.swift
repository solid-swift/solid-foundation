//
//  YAMLDocumentStreamReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData
import SolidIO

/// Async YAML reader that produces document values for a full document stream.
public final class YAMLDocumentStreamReader {

  private let source: any Source
  private let bufferSize: Int
  private var remainingText = ""
  private var allowDirectives = true
  private var requireDocumentStart = false
  private var reachedEOF = false

  public init(source: any Source, bufferSize: Int = BufferedSource.segmentSize) {
    self.source = source
    self.bufferSize = bufferSize
  }

  public func next() async throws -> YAMLValueDocument? {
    while true {
      if let document = try readNextDocument(isFinal: reachedEOF) {
        var anchors: [String: Value] = [:]
        let value = try document.node.toValue(anchors: &anchors)
        return YAMLValueDocument(
          value: value,
          explicitStart: document.explicitStart,
          explicitEnd: document.explicitEnd
        )
      }

      if reachedEOF {
        return nil
      }

      guard let chunk = try await source.read(max: bufferSize) else {
        reachedEOF = true
        continue
      }
      guard let text = String(data: chunk, encoding: .utf8) else {
        throw YAML.DataError.invalidEncoding(.utf8)
      }
      remainingText += text
    }
  }

  private func readNextDocument(isFinal: Bool) throws -> YAMLDocument? {
    guard !remainingText.isEmpty else {
      return nil
    }

    var parser = try YAMLParser(
      text: remainingText,
      allowIncompleteInput: !isFinal,
      allowDirectives: allowDirectives,
      requireDocumentStart: requireDocumentStart
    )
    guard let document = try parser.parseNextDocument() else {
      return nil
    }
    allowDirectives = parser.allowsDirectives
    requireDocumentStart = parser.requiresDocumentStart
    remainingText = parser.remainingText()
    return document
  }
}

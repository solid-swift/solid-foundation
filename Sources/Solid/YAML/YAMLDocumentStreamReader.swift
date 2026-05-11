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
  private var stream = YAMLTokenDocumentStream()
  private var reachedEOF = false

  public init(source: any Source, bufferSize: Int = BufferedSource.segmentSize) {
    self.source = source
    self.bufferSize = bufferSize
  }

  public func next() async throws -> YAMLValueDocument? {
    while true {
      if let document = try stream.readValueDocument() {
        return document
      }

      if reachedEOF {
        return nil
      }

      guard let chunk = try await source.read(max: bufferSize) else {
        reachedEOF = true
        stream.feedInput(Data(), isFinal: true)
        continue
      }
      stream.feedInput(chunk, isFinal: false)
    }
  }
}

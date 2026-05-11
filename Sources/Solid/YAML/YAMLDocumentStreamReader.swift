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

  private let driver: FormatDocumentStreamReaderDriver<YAMLDocumentEventReader>
  private var decoder = ParseDocumentEventDecoder(resolver: YAMLScalarResolver())
  private var pendingDocuments: [YAMLValueDocument] = []
  private var pendingDocumentIndex = 0

  public init(source: any Source, bufferSize: Int = BufferedSource.segmentSize) {
    self.driver = FormatDocumentStreamReaderDriver(
      reader: YAMLDocumentEventReader(),
      source: source,
      bufferSize: bufferSize
    )
  }

  public func next() async throws -> YAMLValueDocument? {
    if let document = popPendingDocument() {
      return document
    }

    while true {
      let status = try await driver.readBatch { events in
        for event in events {
          if let document = try decoder.append(event) {
            pendingDocuments.append(YAMLValueDocument(
              value: document.value,
              explicitStart: document.explicitStart,
              explicitEnd: document.explicitEnd
            ))
          }
        }
      }

      if let document = popPendingDocument() {
        return document
      }

      if status == .endOfStream {
        do {
          try decoder.finish()
        } catch {
          throw YAML.ParseError.incompleteInput(location: nil)
        }

        return nil
      }
    }
  }

  private func popPendingDocument() -> YAMLValueDocument? {
    guard pendingDocumentIndex < pendingDocuments.count else {
      return nil
    }

    let document = pendingDocuments[pendingDocumentIndex]
    pendingDocumentIndex += 1
    if pendingDocumentIndex == pendingDocuments.count {
      pendingDocuments.removeAll(keepingCapacity: true)
      pendingDocumentIndex = 0
    }
    return document
  }
}

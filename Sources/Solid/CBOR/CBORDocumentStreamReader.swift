//
//  CBORDocumentStreamReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/18/26.
//

import Foundation
import SolidData
import SolidIO

/// Async CBOR reader that produces document values from a stream.
public final class CBORDocumentStreamReader {

  public struct Options: Sendable {
    public static let `default` = Self()
    public var undefined: CBORValueReader.Options.Undefined

    public init(undefined: CBORValueReader.Options.Undefined = .throwError) {
      self.undefined = undefined
    }
  }

  private let driver: FormatDocumentStreamReaderDriver<CBORDocumentEventReader>
  private var decoder = ParseDocumentEventDecoder(resolver: CBORScalarResolver())
  private var pendingDocuments: [CBORValueDocument] = []
  private var pendingDocumentIndex = 0

  public init(source: any Source, bufferSize: Int = BufferedSource.segmentSize, options: Options = .default) {
    let reader = CBORDocumentEventReader(options: .init(undefined: options.undefined))
    self.driver = FormatDocumentStreamReaderDriver(reader: reader, source: source, bufferSize: bufferSize)
  }

  public func next() async throws -> CBORValueDocument? {
    if let document = popPendingDocument() {
      return document
    }

    while true {
      let status = try await driver.readBatch { events in
        for event in events {
          if let document = try decoder.append(event) {
            pendingDocuments.append(CBORValueDocument(value: document.value))
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
          throw CBOR.Error.unexpectedEndOfStream
        }

        return nil
      }
    }
  }

  private func popPendingDocument() -> CBORValueDocument? {
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

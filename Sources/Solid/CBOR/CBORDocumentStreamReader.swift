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

  public init(source: any Source, bufferSize: Int = BufferedSource.segmentSize, options: Options = .default) {
    let reader = CBORDocumentEventReader(options: .init(undefined: options.undefined))
    self.driver = FormatDocumentStreamReaderDriver(reader: reader, source: source, bufferSize: bufferSize)
  }

  public func next() async throws -> CBORValueDocument? {
    while let event = try await driver.next() {
      if let document = try decoder.append(event) {
        return CBORValueDocument(value: document.value)
      }
    }

    do {
      try decoder.finish()
    } catch {
      throw CBOR.Error.unexpectedEndOfStream
    }

    return nil
  }
}

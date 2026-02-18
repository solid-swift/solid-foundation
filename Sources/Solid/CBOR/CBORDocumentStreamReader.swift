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

  private let driver: FormatStreamReaderDriver<CBORStreamReader>
  private var decoder = ValueEventDecoder()
  private var hasPendingEvents = false

  public init(source: any Source, bufferSize: Int = BufferedSource.segmentSize, options: Options = .default) {
    let reader = CBORStreamReader(options: .init(undefined: options.undefined))
    self.driver = FormatStreamReaderDriver(reader: reader, source: source, bufferSize: bufferSize)
  }

  public func next() async throws -> CBORValueDocument? {
    while let event = try await driver.next() {
      hasPendingEvents = true
      try decoder.append(event)
      if decoder.isComplete {
        let value = try decoder.finish()
        decoder = ValueEventDecoder()
        hasPendingEvents = false
        return CBORValueDocument(value: value)
      }
    }

    if hasPendingEvents {
      throw CBOR.Error.unexpectedEndOfStream
    }

    return nil
  }
}

//
//  CBORDocumentReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/18/26.
//

import Foundation
import SolidData

/// Synchronous CBOR reader that loads a stream of documents.
public struct CBORDocumentReader {

  public struct Options: Sendable {
    public static let `default` = Self()
    public var undefined: CBORValueReader.Options.Undefined

    public init(undefined: CBORValueReader.Options.Undefined = .throwError) {
      self.undefined = undefined
    }
  }

  private let data: Data
  private let options: Options

  public init(data: Data, options: Options = .default) {
    self.data = data
    self.options = options
  }

  public func readAll() throws -> [CBORValueDocument] {
    var reader = CBORStreamReader(options: .init(undefined: options.undefined))
    var decoder = ValueEventDecoder()
    var documents: [CBORValueDocument] = []
    var input = data
    let isFinal = true
    var done = false
    var hasPendingEvents = false

    try withUnsafeTemporaryAllocation(of: ValueEvent.self, capacity: 64) { buffer in
      while !done {
        var out = OutputSpan<ValueEvent>(buffer: buffer, initializedCount: 0)
        let status = try reader.read(input: input, isFinal: isFinal, output: &out)
        let count = out.finalize(for: buffer)
        if count > 0 {
          hasPendingEvents = true
          for event in buffer[..<count] {
            try decoder.append(event)
            if decoder.isComplete {
              let value = try decoder.finish()
              documents.append(CBORValueDocument(value: value))
              decoder = ValueEventDecoder()
              hasPendingEvents = false
            }
          }
        }

        switch status {
        case .producedOutput:
          input = Data()
        case .needMoreInput:
          throw CBOR.Error.unexpectedEndOfStream
        case .endOfStream:
          done = true
        }
      }
    }

    if hasPendingEvents {
      throw CBOR.Error.unexpectedEndOfStream
    }

    return documents
  }
}

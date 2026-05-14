//
//  FormatDocumentValueReader.swift
//  SolidFoundation
//
//  Created by Codex on 5/9/26.
//

import Foundation

/// Decodes document-framed parse events into value documents from an in-memory buffer.
public struct FormatDocumentValueReader<Reader: ~Copyable & FormatDocumentStreamReader>: ~Copyable {

  private var reader: Reader
  private let data: Data
  private let resolver: any ScalarResolver
  private let unexpectedEndError: () -> any Swift.Error

  public init(
    reader: consuming Reader,
    data: Data,
    resolver: any ScalarResolver,
    unexpectedEndError: @escaping () -> any Swift.Error
  ) {
    self.reader = reader
    self.data = data
    self.resolver = resolver
    self.unexpectedEndError = unexpectedEndError
  }

  public mutating func readAll() throws -> [FormatValueDocument] {
    var decoder = ParseDocumentEventDecoder(resolver: resolver)
    var documents: [FormatValueDocument] = []
    var input = data
    let isFinal = true
    var done = false

    try withUnsafeTemporaryAllocation(of: ParseDocumentEvent.self, capacity: 64) { buffer in
      while !done {
        var out = OutputSpan<ParseDocumentEvent>(buffer: buffer, initializedCount: 0)
        let status = try reader.read(input: input, isFinal: isFinal, output: &out)
        let count = out.finalize(for: buffer)

        if count > 0 {
          for event in buffer[..<count] {
            if let document = try decoder.append(event) {
              documents.append(document)
            }
          }
        }

        switch status {
        case .producedOutput:
          input = Data()
        case .needMoreInput:
          throw unexpectedEndError()
        case .endOfStream:
          done = true
        }
      }
    }

    do {
      try decoder.finish()
    } catch {
      throw unexpectedEndError()
    }

    return documents
  }
}

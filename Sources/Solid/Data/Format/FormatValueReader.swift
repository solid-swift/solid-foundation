//
//  FormatValueReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/15/26.
//

import Foundation

/// A generic synchronous value reader that decodes a ``Value`` from raw `Data`
/// using a ``FormatStreamReader`` pipeline.
///
/// Suitable for YAML and CBOR; JSON uses its own token-based reader.
public struct FormatValueReader<Reader: FormatStreamReader>: FormatReader {

  private var reader: Reader
  private let data: Data
  private let formatValue: Format
  private let unexpectedEndError: @Sendable () -> any Swift.Error

  public init(
    reader: Reader,
    data: Data,
    format: Format,
    unexpectedEndError: @escaping @Sendable () -> any Swift.Error
  ) {
    self.reader = reader
    self.data = data
    self.formatValue = format
    self.unexpectedEndError = unexpectedEndError
  }

  public var format: Format { formatValue }

  public mutating func read() throws -> Value {
    var decoder = ValueEventDecoder()
    var firstValue: Value?

    var done = false
    var input = data
    let isFinal = true

    try withUnsafeTemporaryAllocation(of: ValueEvent.self, capacity: 64) { buffer in
      while !done {
        var out = OutputSpan<ValueEvent>(buffer: buffer, initializedCount: 0)
        let status = try reader.read(input: input, isFinal: isFinal, output: &out)
        let count = out.finalize(for: buffer)
        if count > 0 {
          for event in buffer[..<count] {
            try decoder.append(event)
            if decoder.isComplete {
              let value = try decoder.finish()
              if firstValue == nil {
                firstValue = value
                done = true
                break
              }
              decoder = ValueEventDecoder()
            }
          }
        }

        if done {
          break
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

    if let firstValue {
      return firstValue
    }
    return .null
  }
}

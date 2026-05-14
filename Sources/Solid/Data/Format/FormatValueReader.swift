//
//  FormatValueReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/15/26.
//

import Foundation

/// Errors thrown by the generic synchronous value reader.
public enum FormatValueReaderError: Error, Sendable, Equatable, LocalizedError {

  /// Additional data was found after the root value.
  case trailingData

  public var errorDescription: String? {
    switch self {
    case .trailingData:
      return "Extra data after root value"
    }
  }
}

/// A generic synchronous value reader that decodes a ``Value`` from raw `Data`
/// using a ``FormatStreamReader`` pipeline.
///
/// Used by format-specific value readers that expose a `FormatStreamReader`
/// pipeline.
public struct FormatValueReader<Reader: ~Copyable & FormatStreamReader>: ~Copyable, FormatReader {

  private var reader: Reader
  private let data: Data
  private let formatValue: Format
  private let scalarResolver: (any ScalarResolver)?
  private let unexpectedEndError: @Sendable () -> any Swift.Error
  private let requiresEndOfStream: Bool
  private let trailingDataError: @Sendable () -> any Swift.Error

  public init(
    reader: consuming Reader,
    data: Data,
    format: Format,
    scalarResolver: (any ScalarResolver)? = nil,
    unexpectedEndError: @escaping @Sendable () -> any Swift.Error,
    requiresEndOfStream: Bool = false,
    trailingDataError: @escaping @Sendable () -> any Swift.Error = {
      FormatValueReaderError.trailingData
    }
  ) {
    self.reader = reader
    self.data = data
    self.formatValue = format
    self.scalarResolver = scalarResolver
    self.unexpectedEndError = unexpectedEndError
    self.requiresEndOfStream = requiresEndOfStream
    self.trailingDataError = trailingDataError
  }

  public var format: Format { formatValue }

  public mutating func read() throws -> Value {
    func makeDecoder() -> ParseEventDecoder {
      if let scalarResolver {
        return ParseEventDecoder(resolver: scalarResolver)
      }
      return ParseEventDecoder()
    }

    var decoder = makeDecoder()
    var firstValue: Value?

    var done = false
    var input = data
    let isFinal = true

    try withUnsafeTemporaryAllocation(of: ParseEvent.self, capacity: 64) { buffer in
      while !done {
        var out = OutputSpan<ParseEvent>(buffer: buffer, initializedCount: 0)
        let status = try reader.read(input: input, isFinal: isFinal, output: &out)
        let count = out.finalize(for: buffer)
        if count > 0 {
          for event in buffer[..<count] {
            if firstValue != nil, requiresEndOfStream {
              throw trailingDataError()
            }
            try decoder.append(event)
            if decoder.isComplete {
              let value = try decoder.finish()
              if firstValue == nil {
                firstValue = value
                if !requiresEndOfStream {
                  done = true
                  break
                }
                decoder = makeDecoder()
                continue
              }
              throw trailingDataError()
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
    throw unexpectedEndError()
  }
}

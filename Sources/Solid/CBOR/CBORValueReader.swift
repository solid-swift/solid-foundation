//
//  CBORValueReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/18/26.
//

import Foundation
import SolidData

/// Synchronous CBOR reader that loads into ``Value``.
public struct CBORValueReader: FormatReader {

  public struct Options: Sendable {

    public enum Undefined: Sendable {
      case throwError
      case convertToNull
    }

    public var undefined: Undefined

    public init(undefined: Undefined = .throwError) {
      self.undefined = undefined
    }
  }

  private let data: Data
  private let options: Options

  public init(data: Data, options: Options = Options()) {
    self.data = data
    self.options = options
  }

  public var format: Format { CBOR.format }

  public func read() throws -> Value {
    let reader = CBORStreamReader(options: options)
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
          throw CBOR.Error.unexpectedEndOfStream
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

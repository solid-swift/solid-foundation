//
//  YAMLValueReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData
import SolidIO

/// Synchronous YAML reader that loads into ``Value``.
public struct YAMLValueReader: FormatReader {

  private let text: String

  public init(data: Data) throws {
    guard let text = String(data: data, encoding: .utf8) else {
      throw YAML.DataError.invalidEncoding(.utf8)
    }
    self.text = text
  }

  public init(string: String) {
    self.text = string
  }

  public var format: Format { YAML.format }

  public mutating func read() throws -> Value {
    let data = Data(text.utf8)
    var reader = YAMLStreamReader()
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
          throw YAML.ParseError.invalidSyntax("Unexpected end of document", location: nil)
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

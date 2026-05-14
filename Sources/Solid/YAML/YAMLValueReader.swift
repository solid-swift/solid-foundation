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
public struct YAMLValueReader: ~Copyable, FormatReader {

  private let data: Data

  public init(data: Data) throws {
    guard Self.isValidUTF8(data) else {
      throw YAML.DataError.invalidEncoding(.utf8)
    }
    self.data = data
  }

  public init(string: String) {
    self.data = Data(string.utf8)
  }

  public var format: Format { YAML.format }

  public mutating func read() throws -> Value {
    var stream = YAMLTokenDocumentStream()
    stream.feedInput(data, isFinal: true)

    do {
      guard let first = try stream.readValueDocument() else {
        throw YAML.ParseError.incompleteInput(location: nil)
      }
      if try stream.readValueDocument() != nil {
        throw YAML.ParseError.invalidSyntax("Extra document after root value", location: nil)
      }
      return first.value
    } catch YAML.ParseError.incompleteInput(let location) {
      throw YAML.ParseError.invalidSyntax("Unexpected end of document", location: location)
    }
  }

  private static func isValidUTF8(_ data: Data) -> Bool {
    data.withUnsafeBytes { rawBuffer in
      var parser = Unicode.UTF8.ForwardParser()
      var iterator = rawBuffer.bindMemory(to: UInt8.self).makeIterator()
      while true {
        switch parser.parseScalar(from: &iterator) {
        case .valid:
          continue
        case .emptyInput:
          return true
        case .error:
          return false
        }
      }
    }
  }
}

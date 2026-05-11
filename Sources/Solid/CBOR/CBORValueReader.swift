//
//  CBORValueReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/18/26.
//

import Foundation
import SolidData

/// Synchronous CBOR reader that loads into ``Value``.
public struct CBORValueReader: ~Copyable, FormatReader {

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

  private var reader: FormatValueReader<CBORStreamReader>

  public init(data: Data, options: Options = Options()) {
    self.reader = FormatValueReader(
      reader: CBORStreamReader(options: options),
      data: data,
      format: CBOR.format,
      scalarResolver: CBORScalarResolver(),
      unexpectedEndError: { CBOR.Error.unexpectedEndOfStream },
      requiresEndOfStream: true,
      trailingDataError: {
        CBOR.Error.invalidStructure("Extra data after root value")
      }
    )
  }

  public var format: Format { reader.format }

  public mutating func read() throws -> Value {
    try reader.read()
  }
}

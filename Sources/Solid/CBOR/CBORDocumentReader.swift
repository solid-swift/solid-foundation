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
    var reader = FormatDocumentValueReader(
      reader: CBORDocumentEventReader(options: .init(undefined: options.undefined)),
      data: data,
      resolver: CBORScalarResolver(),
      unexpectedEndError: { CBOR.Error.unexpectedEndOfStream }
    )
    return try reader.readAll().map { CBORValueDocument(value: $0.value) }
  }
}

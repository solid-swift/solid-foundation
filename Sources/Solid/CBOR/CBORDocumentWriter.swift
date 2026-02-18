//
//  CBORDocumentWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/18/26.
//

import Foundation
import SolidData

/// Synchronous CBOR writer that emits document streams.
public final class CBORDocumentWriter {

  public struct Options: Sendable {
    public static let `default` = Self()
    public var deterministic: Bool

    public init(deterministic: Bool = false) {
      self.deterministic = deterministic
    }
  }

  private let options: Options
  private var output = Data()

  public init(options: Options = .default) {
    self.options = options
  }

  public func write(_ document: CBORValueDocument) throws {
    let data = try CBORValueWriter.write(document.value, options: .init(deterministic: options.deterministic))
    output.append(data)
  }

  public func writeAll(_ documents: [CBORValueDocument]) throws {
    for document in documents {
      try write(document)
    }
  }

  public func data() -> Data {
    output
  }
}

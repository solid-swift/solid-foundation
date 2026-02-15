//
//  JSONValueWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/25/25.
//

import Foundation
import SolidData


public struct JSONValueWriter: FormatWriter {

  public struct Options: Sendable {

    public static let `default` = Self()

    /// Determines the shape of tagged values.
    ///
    public enum TagShape: Sendable {
      /// No tags are written.
      ///
      /// Unwraps the tagged value and writes the value directly.
      ///
      case unwrapped
      /// Tags are written as an array of `[tag, value]`.
      ///
      case array
      /// Tags are written as an object of `{ <tagKey>: <tag>, <valueKey>: <value> }`.
      ///
      case object(tagKey: String, valueKey: String)
      /// Tags are written as an object of `{ <tag>: <value> }`.
      case wrapped
    }

    public var tagShape: TagShape

    public init(tagShape: TagShape = .unwrapped) {
      self.tagShape = tagShape
    }
  }

  private let writer: FormatValueWriter<JSONStreamEncoder>

  /// Write a value into a new in-memory Data buffer.
  public static func write(_ value: Value, options: Options = .default) -> Data {
    let writer = JSONValueWriter(options: options)
    return (try? writer.write(value)) ?? Data()
  }

  public init(options: Options = Options()) {
    self.writer = FormatValueWriter(
      format: JSON.format,
      makeEncoder: {
        JSONStreamEncoder(
          writer: JSONEventWriter(options: .init(tagShape: options.tagShape, escapeSlashes: false))
        )
      },
      encodeValue: { value in
        ValueEventEncoder().encode(value)
      }
    )
  }

  public var format: Format { writer.format }

  public func write(_ value: Value) throws -> Data {
    try writer.write(value)
  }
}

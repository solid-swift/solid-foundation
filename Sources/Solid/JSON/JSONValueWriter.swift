//
//  JSONValueWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/25/25.
//

import Foundation
import SolidData


public final class JSONValueWriter: FormatWriter {

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

  let options: Options
  private var output = Data()

  /// Write a value into a new in-memory Data buffer.
  public static func write(_ value: Value, options: Options = .default) -> Data {
    let writer = JSONValueWriter(options: options)
    writer.write(value)
    return writer.data()
  }

  public init(options: Options = Options()) {
    self.options = options
  }

  public var format: Format { JSON.format }

  public func write(_ value: Value) {
    let encoder = ValueEventEncoder()
    let streamEncoder = JSONStreamEncoder(
      writer: JSONEventWriter(options: .init(tagShape: options.tagShape, escapeSlashes: false))
    )
    var buffer = FormatStreamEncoderBuffer(encoder: streamEncoder)
    output = (try? buffer.encode(events: encoder.encode(value))) ?? Data()
  }

  public func data() -> Data {
    output
  }
}

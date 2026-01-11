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

  let tokenWriter: JSONTokenWriter
  let options: Options

  /// Write a value into a new in-memory Data buffer.
  public static func write(_ value: Value, options: Options = .default) -> Data {
    let writer = JSONValueWriter()
    writer.write(value)
    return writer.data()
  }

  public init(options: Options = Options()) {
    self.tokenWriter = JSONTokenWriter()
    self.options = options
  }

  public var format: Format { JSON.format }

  public func write(_ value: Value) {
    switch value {

    case .null:
      tokenWriter.writeToken(.scalar(.null))

    case .bool(let bool):
      tokenWriter.writeToken(.scalar(.bool(bool)))

    case .number(let number):
      tokenWriter.writeToken(.scalar(.number(.init(number))))

    case .string(let string):
      tokenWriter.writeToken(.scalar(.string(string)))

    case .bytes(let data):
      tokenWriter.writeToken(.scalar(.string(data.base64EncodedString())))

    case .array(let array):

      tokenWriter.writeToken(.beginArray)

      for (idx, element) in array.enumerated() {

        write(element)

        if idx < array.count - 1 {
          tokenWriter.writeToken(.elementSeparator)
        }
      }

      tokenWriter.writeToken(.endArray)

    case .object(let object):

      tokenWriter.writeToken(.beginObject)

      for (idx, entry) in object.enumerated() {

        write(entry.key)
        tokenWriter.writeToken(.pairSeparator)
        write(entry.value)

        if idx < object.values.count - 1 {
          tokenWriter.writeToken(.elementSeparator)
        }
      }

      tokenWriter.writeToken(.endObject)

    case .tagged(let tag, let value):
      switch options.tagShape {
      case .unwrapped:
        write(value)
      case .array:
        write([tag, value])
      case .object(let tagKey, let valueKey):
        write([.string(tagKey): tag, .string(valueKey): value])
      case .wrapped:
        write([tag: value])
      }
    }
  }

  public func data() -> Data {
    Data(tokenWriter.output.value.utf8)
  }
}

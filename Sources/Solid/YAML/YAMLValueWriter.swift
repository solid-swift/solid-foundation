//
//  YAMLValueWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/30/26.
//

import Foundation
import SolidData

/// Synchronous YAML writer that renders ``Value`` instances.
public final class YAMLValueWriter: FormatWriter {

  public struct Options: Sendable {
    public static let `default` = Self()
    public var indent: Int

    public init(indent: Int = 2) {
      self.indent = indent
    }
  }

  private let options: Options
  private var output = Data()

  /// Write a value into a new in-memory `Data` buffer.
  public static func write(_ value: Value, options: Options = .default) throws -> Data {
    let writer = YAMLValueWriter(options: options)
    try writer.write(value)
    return writer.data()
  }

  public init(options: Options = .default) {
    self.options = options
  }

  public var format: Format { YAML.format }

  public func write(_ value: Value) throws {
    let encoder = ValueEventEncoder()
    let streamEncoder = YAMLStreamEncoder(
      options: .init(indent: options.indent, allowImplicitTyping: false)
    )
    var buffer = FormatStreamEncoderBuffer(encoder: streamEncoder)
    output = try buffer.encode(events: encoder.encode(value))
  }

  /// Rendered YAML bytes.
  public func data() -> Data {
    output
  }
}

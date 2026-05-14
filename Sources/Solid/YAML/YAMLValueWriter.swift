//
//  YAMLValueWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/30/26.
//

import Foundation
import SolidData

/// Synchronous YAML writer that renders ``Value`` instances.
public struct YAMLValueWriter: FormatWriter {

  public struct Options: Sendable {
    public static let `default` = Self()
    public var indent: Int

    public init(indent: Int = 2) {
      self.indent = indent
    }
  }

  private let writer: FormatValueWriter<YAMLStreamEncoder>

  /// Write a value into a new in-memory `Data` buffer.
  public static func write(_ value: Value, options: Options = .default) throws -> Data {
    let writer = YAMLValueWriter(options: options)
    return try writer.write(value)
  }

  public init(options: Options = .default) {
    self.writer = FormatValueWriter(
      format: YAML.format,
      makeEncoder: {
        YAMLStreamEncoder(
          writer: YAMLEventWriter(options: .init(indent: options.indent, allowImplicitTyping: false))
        )
      },
      emitValue: { value, emit in
        try EmitEventEncoder().emit(value, to: emit)
      }
    )
  }

  public var format: Format { writer.format }

  public func write(_ value: Value) throws -> Data {
    try writer.write(value)
  }
}

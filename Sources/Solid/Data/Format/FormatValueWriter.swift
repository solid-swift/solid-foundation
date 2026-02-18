//
//  FormatValueWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/15/26.
//

import Foundation

/// A generic synchronous value writer that encodes a ``Value`` through a
/// ``FormatStreamEncoder`` pipeline.
///
/// Each format module provides a concrete type (or typealias) that configures
/// the encoder factory and event encoding closures.
public struct FormatValueWriter<Encoder: FormatStreamEncoder>: FormatWriter {

  private let makeEncoder: @Sendable () -> Encoder
  private let encodeValue: @Sendable (Value) throws -> [ValueEvent]
  private let formatValue: Format

  public init(
    format: Format,
    makeEncoder: @escaping @Sendable () -> Encoder,
    encodeValue: @escaping @Sendable (Value) throws -> [ValueEvent]
  ) {
    self.formatValue = format
    self.makeEncoder = makeEncoder
    self.encodeValue = encodeValue
  }

  public var format: Format { formatValue }

  public func write(_ value: Value) throws -> Data {
    let events = try encodeValue(value)
    var buffer = FormatStreamEncoderBuffer(encoder: makeEncoder())
    return try buffer.encode(events: events)
  }
}

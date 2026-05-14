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
  private let emitValue: (Value, (EmitEvent) throws -> Void) throws -> Void
  private let formatValue: Format
  private let bufferSize: Int
  private let estimateOutputCapacity: @Sendable (Value) -> Int?

  public init(
    format: Format,
    makeEncoder: @escaping @Sendable () -> Encoder,
    encodeValue: @escaping @Sendable (Value) throws -> [EmitEvent],
    bufferSize: Int = FormatStreamEncoderBuffer<Encoder>.defaultBufferSize,
    estimateOutputCapacity: @escaping @Sendable (Value) -> Int? = { _ in nil }
  ) {
    self.formatValue = format
    self.makeEncoder = makeEncoder
    self.bufferSize = bufferSize
    self.estimateOutputCapacity = estimateOutputCapacity
    self.emitValue = { value, emit in
      for event in try encodeValue(value) {
        try emit(event)
      }
    }
  }

  public init(
    format: Format,
    makeEncoder: @escaping @Sendable () -> Encoder,
    emitValue: @escaping (Value, (EmitEvent) throws -> Void) throws -> Void,
    bufferSize: Int = FormatStreamEncoderBuffer<Encoder>.defaultBufferSize,
    estimateOutputCapacity: @escaping @Sendable (Value) -> Int? = { _ in nil }
  ) {
    self.formatValue = format
    self.makeEncoder = makeEncoder
    self.emitValue = emitValue
    self.bufferSize = bufferSize
    self.estimateOutputCapacity = estimateOutputCapacity
  }

  public var format: Format { formatValue }

  public func write(_ value: Value) throws -> Data {
    var buffer = FormatStreamEncoderBuffer(encoder: makeEncoder(), bufferSize: bufferSize)
    return try buffer.encode(estimatedCapacity: estimateOutputCapacity(value)) { emit in
      try emitValue(value, emit)
    }
  }
}

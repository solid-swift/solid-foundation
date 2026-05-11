//
//  CBORValueWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/18/26.
//

import Foundation
import SolidData

/// Synchronous CBOR writer that renders ``Value`` instances.
public struct CBORValueWriter: FormatWriter {

  public struct Options: Sendable {

    public static let `default` = Self()

    public var deterministic: Bool
    public var includeContainerSizes: Bool

    public init(deterministic: Bool = false, includeContainerSizes: Bool = true) {
      self.deterministic = deterministic
      self.includeContainerSizes = includeContainerSizes
    }
  }

  private let writer: FormatValueWriter<CBORStreamEncoder>

  /// Write a value into a new in-memory `Data` buffer.
  public static func write(_ value: Value, options: Options = .default) throws -> Data {
    let writer = CBORValueWriter(options: options)
    return try writer.write(value)
  }

  public init(options: Options = .default) {
    self.writer = FormatValueWriter(
      format: CBOR.format,
      makeEncoder: {
        CBORStreamEncoder(
          writer: CBOREncoder(
            options: .init(deterministic: options.deterministic, deterministicMode: .none)
          )
        )
      },
      emitValue: { value, emit in
        let encoder = CBOREmitEventEncoder(
          deterministic: options.deterministic,
          includeContainerSizes: options.includeContainerSizes
        )
        try encoder.emit(value, to: emit)
      }
    )
  }

  public var format: Format { writer.format }

  public func write(_ value: Value) throws -> Data {
    try writer.write(value)
  }
}

private struct CBOREmitEventEncoder {
  let deterministic: Bool
  let includeContainerSizes: Bool

  func encode(_ value: Value) throws -> [EmitEvent] {
    var events: [EmitEvent] = []
    try emit(value) { event in
      events.append(event)
    }
    return events
  }

  func encode(_ value: Value, into events: inout [EmitEvent]) throws {
    try emit(value) { event in
      events.append(event)
    }
  }

  func emit(_ value: Value, to emit: (EmitEvent) throws -> Void) throws {
    switch value {
    case .tagged(let tags, let inner):
      for tag in tags {
        try emit(.tag(tag))
      }
      try self.emit(inner, to: emit)

    case .array(let array):
      try emit(.beginArray(count: includeContainerSizes ? array.count : nil))
      for item in array {
        try self.emit(item, to: emit)
      }
      try emit(.endArray)

    case .object(let object):
      try emit(.beginObject(count: includeContainerSizes ? object.count : nil))
      if deterministic {
        let entries = try object.map { key, value in
          (try deterministicBytes(of: key), key, value)
        }
        for (_, key, value) in entries.sorted(by: { $0.0.lexicographicallyPrecedes($1.0) }) {
          try emit(.scalar(key))
          try self.emit(value, to: emit)
        }
      } else {
        for (key, value) in object {
          try emit(.scalar(key))
          try self.emit(value, to: emit)
        }
      }
      try emit(.endObject)

    default:
      try emit(.scalar(value))
    }
  }

  private func deterministicBytes(of value: Value) throws -> Data {
    try CBORDeterministicKeyEncoder.encode(value)
  }
}

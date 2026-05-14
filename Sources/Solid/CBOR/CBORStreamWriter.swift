//
//  CBORStreamWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/17/26.
//

import Foundation
import SolidData
import SolidIO

/// Async CBOR stream writer that consumes ``EmitEvent`` values.
public final class CBORStreamWriter: FormatStreamWriter {

  public struct Options: Sendable {

    public static let `default` = Self()

    /// Produce RFC 8949 core deterministic encoding.
    public var deterministic: Bool

    public init(deterministic: Bool = false) {
      self.deterministic = deterministic
    }
  }

  public enum Error: Swift.Error {
    case invalidEventSequence(String)
    case incompleteCBOR
    case alreadyFinished
    case invalidTagValue

    fileprivate static func from(_ error: CBOREncoder.Error) -> Self {
      switch error {
      case .invalidEventSequence(let message):
        return .invalidEventSequence(message)
      case .incompleteCBOR:
        return .incompleteCBOR
      case .alreadyFinished:
        return .alreadyFinished
      case .invalidTagValue:
        return .invalidTagValue
      }
    }
  }

  private let options: Options
  private let adapter: FormatStreamWriterAdapter<CBORStreamEncoder>

  public init(sink: any Sink, options: Options = .default, bufferSize: Int = BufferedSink.segmentSize) {
    self.options = options
    self.adapter = Self.makeAdapter(
      sink: sink,
      options: options,
      bufferSize: bufferSize,
      sortMapEvents: options.deterministic
    )
  }

  private static func makeAdapter(
    sink: any Sink,
    options: Options,
    bufferSize: Int,
    sortMapEvents: Bool
  ) -> FormatStreamWriterAdapter<CBORStreamEncoder> {
    FormatStreamWriterAdapter(
      encoder: CBORStreamEncoder(
        writer: CBOREncoder(
          options: .init(
            deterministic: options.deterministic,
            deterministicMode: sortMapEvents ? .sortMapEvents : .none
          )
        )
      ),
      sink: sink,
      bufferSize: bufferSize,
      alreadyFinishedError: { Error.alreadyFinished },
      mapError: { error in
        if let cborError = error as? CBOREncoder.Error {
          return Error.from(cborError)
        }
        return error
      }
    )
  }

  public var format: Format { adapter.format }

  public func write(_ event: EmitEvent) async throws {
    try await adapter.write(event)
  }

  public func writeEvents<Cursor: EmitEventCursor>(_ cursor: inout Cursor) async throws {
    try await adapter.write(events: &cursor)
  }

  public func writeValue(_ value: Value) async throws {
    if options.deterministic {
      var cursor = CBORDeterministicValueEmitEventCursor(value)
      try await adapter.write(events: &cursor)
    } else {
      var cursor = ValueEmitEventCursor(value)
      try await writeEvents(&cursor)
    }
  }

  public func finish() async throws {
    try await adapter.finish()
  }

  public func close() async throws {
    try await adapter.close()
  }
}

private struct CBORDeterministicValueEmitEventCursor: EmitEventCursor {

  private enum Frame {
    case value(Value)
    case tags(tags: [Value], index: Int, value: Value)
    case array(IndexingIterator<Value.Array>)
    case object(iterator: IndexingIterator<[(key: Value, value: Value)]>, pendingValue: Value?)
    case endArray
    case endObject
  }

  private var stack: [Frame]

  init(_ value: Value) {
    self.stack = [.value(value)]
  }

  mutating func next() throws -> EmitEvent? {
    while let frame = stack.popLast() {
      switch frame {
      case .value(let value):
        if let event = try push(value) {
          return event
        }

      case .tags(let tags, let index, let value):
        guard index < tags.count else {
          stack.append(.value(value))
          continue
        }
        stack.append(.tags(tags: tags, index: index + 1, value: value))
        return .tag(tags[index])

      case .array(var iterator):
        guard let value = iterator.next() else {
          continue
        }
        stack.append(.array(iterator))
        stack.append(.value(value))

      case .object(var iterator, let pendingValue):
        if let pendingValue {
          stack.append(.object(iterator: iterator, pendingValue: nil))
          stack.append(.value(pendingValue))
          continue
        }
        guard let entry = iterator.next() else {
          continue
        }
        stack.append(.object(iterator: iterator, pendingValue: entry.value))
        return .scalar(entry.key)

      case .endArray:
        return .endArray

      case .endObject:
        return .endObject
      }
    }

    return nil
  }

  private mutating func push(_ value: Value) throws -> EmitEvent? {
    switch value {
    case .tagged(let tags, let inner):
      guard !tags.isEmpty else {
        stack.append(.value(inner))
        return nil
      }
      stack.append(.tags(tags: tags, index: 1, value: inner))
      return .tag(tags[0])

    case .array(let array):
      stack.append(.endArray)
      stack.append(.array(array.makeIterator()))
      return .beginArray(count: array.count)

    case .object(let object):
      let entries = try object.enumerated().map { index, entry in
        (
          keyBytes: try CBORDeterministicKeyEncoder.encode(entry.key),
          order: index,
          key: entry.key,
          value: entry.value
        )
      }
      .sorted {
        CBORDeterministicKeyEncoder.isOrderedBefore(
          $0.keyBytes,
          order: $0.order,
          $1.keyBytes,
          order: $1.order
        )
      }
      .map { (key: $0.key, value: $0.value) }

      stack.append(.endObject)
      stack.append(.object(iterator: entries.makeIterator(), pendingValue: nil))
      return .beginObject(count: object.count)

    default:
      return .scalar(value)
    }
  }
}

//
//  JSONStreamWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import Foundation
import SolidData
import SolidIO

/// Async JSON stream writer that consumes ``EmitEvent`` values.
public final class JSONStreamWriter: FormatStreamWriter {

  public typealias TagShape = JSONValueWriter.Options.TagShape

  public struct Options: Sendable {

    public static let `default` = Self()

    public var tagShape: TagShape
    public var escapeSlashes: Bool

    public init(tagShape: TagShape = .unwrapped, escapeSlashes: Bool = false) {
      self.tagShape = tagShape
      self.escapeSlashes = escapeSlashes
    }
  }

  public enum Error: Swift.Error {
    case invalidEventSequence(String)
    case invalidObjectKey
    case invalidTagType
    case invalidNumber
    case incompleteJSON
    case alreadyFinished
  }

  private let adapter: FormatStreamWriterAdapter<JSONStreamEncoder>

  public init(sink: any Sink, bufferSize: Int = BufferedSink.segmentSize, options: Options = .default) {
    self.adapter = FormatStreamWriterAdapter(
      encoder: JSONStreamEncoder(writer: JSONEventWriter(options: options)),
      sink: sink,
      bufferSize: bufferSize,
      alreadyFinishedError: { Error.alreadyFinished }
    )
  }

  public var format: Format { adapter.format }

  public func write(_ event: EmitEvent) async throws {
    try await adapter.write(event)
  }

  public func finish() async throws {
    try await adapter.finish()
  }

  public func close() async throws {
    try await adapter.close()
  }
}

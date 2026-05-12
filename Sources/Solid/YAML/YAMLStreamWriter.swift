//
//  YAMLStreamWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData
import SolidIO

/// Async YAML stream writer that consumes ``EmitEvent`` values.
public final class YAMLStreamWriter: FormatStreamWriter {

  static let anchorTagPrefix = YAMLEventWriter.anchorTagPrefix

  public struct Options: Sendable {
    public static let `default` = Self()
    public var indent: Int
    public var forceBlockCollections: Bool
    public var allowImplicitTyping: Bool
    public var allowDocumentMarkerPrefix: Bool

    public init(
      indent: Int = 2,
      forceBlockCollections: Bool = false,
      allowImplicitTyping: Bool = true,
      allowDocumentMarkerPrefix: Bool = false
    ) {
      self.indent = indent
      self.forceBlockCollections = forceBlockCollections
      self.allowImplicitTyping = allowImplicitTyping
      self.allowDocumentMarkerPrefix = allowDocumentMarkerPrefix
    }
  }

  private let adapter: FormatStreamWriterAdapter<YAMLStreamEncoder>

  public init(sink: any Sink, bufferSize: Int = BufferedSink.segmentSize, options: Options = .default) {
    self.adapter = FormatStreamWriterAdapter(
      encoder: YAMLStreamEncoder(writer: YAMLEventWriter(options: options)),
      sink: sink,
      bufferSize: bufferSize,
      alreadyFinishedError: { YAML.EmitError.invalidState("Writer already finished") }
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
    var cursor = ValueEmitEventCursor(value)
    try await writeEvents(&cursor)
  }

  public func finish() async throws {
    try await adapter.finish()
  }

  public func close() async throws {
    try await adapter.close()
  }
}

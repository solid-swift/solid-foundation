//
//  YAMLDocumentStreamWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData
import SolidIO

/// Async YAML writer that emits full document streams.
public final class YAMLDocumentStreamWriter {

  public struct Options: Sendable {
    public static let `default` = Self()
    public var indent: Int

    public init(indent: Int = 2) {
      self.indent = indent
    }
  }

  private let sink: any Sink
  private let bufferSize: Int
  private let options: Options
  private var wroteDocument = false
  private var atLineStart = true

  public init(sink: any Sink, bufferSize: Int = BufferedSink.segmentSize, options: Options = .default) {
    self.sink = sink
    self.bufferSize = bufferSize
    self.options = options
  }

  public func write(_ document: YAMLValueDocument) async throws {
    let needsStart = document.explicitStart || wroteDocument
    if needsStart {
      try await writeMarkerLine("---")
    } else if !atLineStart {
      try await appendString("\n")
    }

    let writer = YAMLStreamWriter(
      sink: sink,
      bufferSize: bufferSize,
      options: .init(
        indent: options.indent,
        allowDocumentMarkerPrefix: !needsStart
      )
    )
    let encoder = ValueEventEncoder()
    let events = encoder.encode(document.value)
    for event in events {
      try await writer.write(event)
    }
    try await writer.finish()
    atLineStart = false

    if document.explicitEnd {
      try await writeMarkerLine("...")
    }
    wroteDocument = true
  }

  public func finish() async throws {
    if !atLineStart {
      try await appendString("\n")
    }
  }

  public func close() async throws {
    try await finish()
    try await sink.close()
  }

  private func writeMarkerLine(_ marker: String) async throws {
    if !atLineStart {
      try await appendString("\n")
    }
    try await appendString(marker)
    try await appendString("\n")
    atLineStart = true
  }

  private func appendString(_ string: String) async throws {
    let data = Data(string.utf8)
    try await sink.write(data: data)
    atLineStart = string.hasSuffix("\n")
  }
}

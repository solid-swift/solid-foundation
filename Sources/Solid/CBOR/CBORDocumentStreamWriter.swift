//
//  CBORDocumentStreamWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/18/26.
//

import Foundation
import SolidData
import SolidIO

/// Async CBOR writer that emits document streams.
public final class CBORDocumentStreamWriter {

  public struct Options: Sendable {
    public static let `default` = Self()
    public var deterministic: Bool

    public init(deterministic: Bool = false) {
      self.deterministic = deterministic
    }
  }

  private let sink: any Sink
  private let bufferSize: Int
  private let options: Options

  public init(sink: any Sink, bufferSize: Int = BufferedSink.segmentSize, options: Options = .default) {
    self.sink = sink
    self.bufferSize = bufferSize
    self.options = options
  }

  public func write(_ document: CBORValueDocument) async throws {
    let writer = CBORStreamWriter(
      sink: sink,
      options: .init(deterministicMode: options.deterministic ? .buffered() : .none),
      bufferSize: bufferSize
    )
    let encoder = ValueEventEncoder()
    let events = encoder.encode(document.value)
    for event in events {
      try await writer.write(event)
    }
    try await writer.finish()
  }

  public func finish() async throws {
    // CBOR document streams have no terminal marker.
  }

  public func close() async throws {
    try await sink.close()
  }
}

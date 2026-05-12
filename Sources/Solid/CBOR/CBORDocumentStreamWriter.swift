//
//  CBORDocumentStreamWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/18/26.
//

import Foundation
import SolidData
import SolidIO
import Synchronization

/// Async CBOR writer that emits document streams.
public final class CBORDocumentStreamWriter: @unchecked Sendable {

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
  private let operationInProgress = Mutex(false)
  private var finished = false
  private var closeAttempted = false

  public init(sink: any Sink, bufferSize: Int = BufferedSink.segmentSize, options: Options = .default) {
    self.sink = sink
    self.bufferSize = bufferSize
    self.options = options
  }

  public func write(_ document: CBORValueDocument) async throws {
    try beginOperation()
    defer { endOperation() }

    guard !finished, !closeAttempted else {
      throw IOError.streamClosed
    }

    let writer = CBORStreamWriter(
      sink: sink,
      options: .init(deterministicMode: options.deterministic ? .buffered() : .none),
      bufferSize: bufferSize
    )
    try await writer.writeValue(document.value)
    try await writer.finish()
  }

  public func finish() async throws {
    try beginOperation()
    defer { endOperation() }

    guard !closeAttempted else {
      throw IOError.streamClosed
    }

    // CBOR document streams have no terminal marker.
    finished = true
  }

  public func close() async throws {
    try beginOperation()
    defer { endOperation() }

    guard !closeAttempted else {
      throw IOError.streamClosed
    }

    finished = true
    closeAttempted = true
    try await sink.close()
  }

  private func beginOperation() throws {
    let began = operationInProgress.withLock { operationInProgress in
      guard !operationInProgress else { return false }
      operationInProgress = true
      return true
    }
    guard began else { throw FormatStreamDriverError.operationInProgress }
  }

  private func endOperation() {
    operationInProgress.withLock { $0 = false }
  }
}

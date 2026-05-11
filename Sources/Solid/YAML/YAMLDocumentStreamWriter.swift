//
//  YAMLDocumentStreamWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData
import SolidIO
import Synchronization

/// Async YAML writer that emits full document streams.
public final class YAMLDocumentStreamWriter: @unchecked Sendable {

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
  private let operationInProgress = Mutex(false)
  private var wroteDocument = false
  private var atLineStart = true
  private var finished = false
  private var closeAttempted = false

  public init(sink: any Sink, bufferSize: Int = BufferedSink.segmentSize, options: Options = .default) {
    self.sink = sink
    self.bufferSize = bufferSize
    self.options = options
  }

  public func write(_ document: YAMLValueDocument) async throws {
    try beginOperation()
    defer { endOperation() }

    guard !finished, !closeAttempted else {
      throw IOError.streamClosed
    }

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
        allowImplicitTyping: false,
        allowDocumentMarkerPrefix: !needsStart
      )
    )
    let encoder = EmitEventEncoder()
    try await writer.writeEvents { emit in
      try await encoder.emit(document.value, to: emit)
    }
    try await writer.finish()
    atLineStart = false

    if document.explicitEnd {
      try await writeMarkerLine("...")
    }
    wroteDocument = true
  }

  public func finish() async throws {
    try beginOperation()
    defer { endOperation() }

    guard !closeAttempted else {
      throw IOError.streamClosed
    }

    try await finishImpl()
  }

  public func close() async throws {
    try beginOperation()
    defer { endOperation() }

    guard !closeAttempted else {
      throw IOError.streamClosed
    }

    try await finishImpl()
    closeAttempted = true
    try await sink.close()
  }

  private func finishImpl() async throws {
    guard !finished else {
      return
    }
    if !atLineStart {
      try await appendString("\n")
    }
    finished = true
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
    guard !string.isEmpty else { return }
    var data = Data()
    data.reserveCapacity(string.utf8.count)
    data.append(contentsOf: string.utf8)
    try await sink.write(data: data)
    atLineStart = string.utf8.last == 0x0A
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

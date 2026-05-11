//
//  FormatDocumentStreamReader.swift
//  SolidFoundation
//
//  Created by Codex on 4/27/26.
//

import Collections
import Foundation
import SolidIO
import Synchronization

/// Streaming reader for document-framed parse events.
public protocol FormatDocumentStreamReader: ~Copyable {
  var format: Format { get }

  mutating func read(
    input: Data,
    isFinal: Bool,
    output: inout OutputSpan<ParseDocumentEvent>
  ) throws -> FormatStreamReadStatus
}

/// Async driver that feeds a document-framed stream reader from a ``Source``.
public final class FormatDocumentStreamReaderDriver<Reader: ~Copyable & FormatDocumentStreamReader>: @unchecked Sendable {

  private var reader: Reader
  private let source: any Source
  private let bufferSize: Int
  private let outputBuffer: UnsafeMutableBufferPointer<ParseDocumentEvent>
  private let operationInProgress = Mutex(false)
  private var queue: Deque<ParseDocumentEvent> = []
  private var reachedEOF = false
  private var finished = false
  private var terminalError: (any Error)?

  public init(
    reader: consuming Reader,
    source: any Source,
    bufferSize: Int = BufferedSource.segmentSize,
    outputCapacity: Int = 64
  ) {
    precondition(bufferSize > 0, "bufferSize must be greater than zero")
    precondition(outputCapacity > 0, "outputCapacity must be greater than zero")

    self.reader = reader
    self.source = source
    self.bufferSize = bufferSize
    self.outputBuffer = UnsafeMutableBufferPointer<ParseDocumentEvent>.allocate(capacity: outputCapacity)
  }

  deinit {
    outputBuffer.deallocate()
  }

  public func next() async throws -> ParseDocumentEvent? {
    try beginOperation()
    defer { endOperation() }

    if let terminalError {
      throw terminalError
    }

    do {
      return try await nextEvent()
    } catch {
      terminalError = error
      finished = true
      queue.removeAll()
      throw error
    }
  }

  /// Reads the next available batch of document-framed parse events.
  ///
  /// The event buffer passed to `consume` is valid only for the duration of the
  /// closure. Use this in hot paths to avoid one async call per event.
  @discardableResult
  public func readBatch(
    _ consume: (UnsafeBufferPointer<ParseDocumentEvent>) throws -> Void
  ) async throws -> FormatStreamReadStatus {
    try beginOperation()
    defer { endOperation() }

    if let terminalError {
      throw terminalError
    }

    let result: (status: FormatStreamReadStatus, count: Int)
    do {
      result = try await nextBatch()
    } catch {
      terminalError = error
      finished = true
      queue.removeAll()
      throw error
    }

    if result.count > 0 {
      try consume(UnsafeBufferPointer(rebasing: outputBuffer[..<result.count]))
    }

    return result.status
  }

  private func nextEvent() async throws -> ParseDocumentEvent? {
    if !queue.isEmpty {
      return queue.removeFirst()
    }

    let result = try await nextBatch()
    guard result.count > 0 else {
      return nil
    }

    if result.count > 1 {
      queue.append(contentsOf: outputBuffer[1..<result.count])
    }

    return outputBuffer[0]
  }

  private func nextBatch() async throws -> (status: FormatStreamReadStatus, count: Int) {
    if !queue.isEmpty {
      return drainQueuedBatch()
    }

    guard !finished else { return (.endOfStream, 0) }

    while true {
      let input: Data
      let isFinal: Bool
      if reachedEOF {
        input = Data()
        isFinal = true
      } else if let chunk = try await source.read(max: bufferSize) {
        input = chunk
        isFinal = false
      } else {
        reachedEOF = true
        input = Data()
        isFinal = true
      }

      var out = OutputSpan<ParseDocumentEvent>(buffer: outputBuffer, initializedCount: 0)
      let status = try reader.read(input: input, isFinal: isFinal, output: &out)
      let count = out.finalize(for: outputBuffer)
      if status == .endOfStream {
        finished = true
      }

      if count > 0 {
        return (status == .endOfStream ? .endOfStream : .producedOutput, count)
      }

      if finished {
        return (.endOfStream, 0)
      }
    }
  }

  private func drainQueuedBatch() -> (status: FormatStreamReadStatus, count: Int) {
    var out = OutputSpan<ParseDocumentEvent>(buffer: outputBuffer, initializedCount: 0)
    while !queue.isEmpty, !out.isFull {
      out.append(queue.removeFirst())
    }

    return (.producedOutput, out.finalize(for: outputBuffer))
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

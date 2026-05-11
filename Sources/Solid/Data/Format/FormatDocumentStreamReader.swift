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

  private func nextEvent() async throws -> ParseDocumentEvent? {
    if !queue.isEmpty {
      return queue.removeFirst()
    }
    guard !finished else { return nil }

    while queue.isEmpty {
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
        queue.append(contentsOf: outputBuffer[..<count])
        break
      }

      if finished {
        break
      }
    }

    return queue.isEmpty ? nil : queue.removeFirst()
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

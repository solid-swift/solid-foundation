//
//  FormatStreamReaderDriver.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import Collections
import Foundation
import SolidIO

/// Async driver that feeds a synchronous ``FormatStreamReader`` from a ``Source``.
public final class FormatStreamReaderDriver<Reader: FormatStreamReader> {

  private var reader: Reader
  private let source: any Source
  private let bufferSize: Int
  private let outputCapacity: Int
  private let outputBuffer: UnsafeMutableBufferPointer<ValueEvent>
  private var queue: Deque<ValueEvent> = []
  private var reachedEOF = false
  private var finished = false

  public init(
    reader: Reader,
    source: any Source,
    bufferSize: Int = BufferedSource.segmentSize,
    outputCapacity: Int = 64
  ) {
    self.reader = reader
    self.source = source
    self.bufferSize = bufferSize
    self.outputCapacity = outputCapacity
    self.outputBuffer = UnsafeMutableBufferPointer<ValueEvent>.allocate(capacity: outputCapacity)
  }

  deinit {
    outputBuffer.deallocate()
  }

  public func next() async throws -> ValueEvent? {
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

      var out = OutputSpan<ValueEvent>(buffer: outputBuffer, initializedCount: 0)
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
}

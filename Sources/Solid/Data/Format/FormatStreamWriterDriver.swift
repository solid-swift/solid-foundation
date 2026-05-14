//
//  FormatStreamWriterDriver.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/18/26.
//

import Foundation
import SolidIO
import Synchronization

/// Async driver that feeds a synchronous ``FormatStreamEncoder`` to a ``Sink``.
public final class FormatStreamWriterDriver<Encoder: FormatStreamEncoder>: FormatStreamWriter, @unchecked Sendable {

  private var encoder: Encoder
  private let streamFormat: Format
  private let sink: any Sink
  private let bufferSize: Int
  private var buffer: [UInt8]
  private var outputData = Data()
  private let operationInProgress = Mutex(false)
  private var finished = false
  private var closeAttempted = false

  public init(
    encoder: Encoder,
    sink: any Sink,
    bufferSize: Int = BufferedSink.segmentSize
  ) {
    precondition(bufferSize > 0, "bufferSize must be greater than zero")

    self.streamFormat = encoder.format
    self.encoder = encoder
    self.sink = sink
    self.bufferSize = bufferSize
    self.buffer = [UInt8](repeating: 0, count: bufferSize)
    self.outputData.reserveCapacity(bufferSize)
  }

  public var format: Format { streamFormat }

  public func write(_ event: EmitEvent) async throws {
    try beginOperation()
    defer { endOperation() }

    guard !finished else { throw IOError.streamClosed }

    do {
      try await encodeAndWrite(event)
    } catch {
      finished = true
      throw error
    }
  }

  public func write<Cursor: EmitEventCursor>(events cursor: inout Cursor) async throws {
    try beginOperation()
    defer { endOperation() }

    guard !finished else { throw IOError.streamClosed }

    do {
      outputData.removeAll(keepingCapacity: true)
      while let event = try cursor.next() {
        try await encodeIntoOutputData(event)
      }
      try await flushOutputData()
    } catch {
      finished = true
      throw error
    }
  }

  public func write(
    _ produceEvents: (_ emit: (EmitEvent) async throws -> Void) async throws -> Void
  ) async throws {
    try beginOperation()
    defer { endOperation() }

    guard !finished else { throw IOError.streamClosed }

    do {
      try await produceEvents { event in
        try await self.encodeAndWrite(event)
      }
    } catch {
      finished = true
      throw error
    }
  }

  private func encodeAndWrite(_ event: EmitEvent) async throws {
    outputData.removeAll(keepingCapacity: true)
    try await encodeIntoOutputData(event)
    try await flushOutputData()
  }

  private func encodeIntoOutputData(_ event: EmitEvent) async throws {
    var done = false
    while !done {
      var status: FormatStreamEncodeStatus = .producedOutput

      try buffer.withUnsafeMutableBufferPointer { ptr in
        var out = OutputSpan<UInt8>(buffer: ptr, initializedCount: 0)
        status = try encoder.encode(event, output: &out)
        let count = out.finalize(for: ptr)
        if count > 0, let base = ptr.baseAddress {
          outputData.append(base, count: count)
        }
      }

      if outputData.count >= bufferSize {
        try await flushOutputData()
      }

      switch status {
      case .producedOutput:
        done = true
      case .needMoreOutputSpace:
        continue
      case .endOfStream:
        finished = true
        done = true
      }
    }
  }

  private func flushOutputData() async throws {
    guard !outputData.isEmpty else { return }
    try await sink.write(data: outputData)
    outputData.removeAll(keepingCapacity: true)
  }

  public func finish() async throws {
    try beginOperation()
    defer { endOperation() }

    guard !finished else { throw IOError.streamClosed }

    var done = false
    while !done {
      var status: FormatStreamEncodeStatus = .producedOutput
      outputData.removeAll(keepingCapacity: true)

      do {
        try buffer.withUnsafeMutableBufferPointer { ptr in
          var out = OutputSpan<UInt8>(buffer: ptr, initializedCount: 0)
          status = try encoder.finish(output: &out)
          let count = out.finalize(for: ptr)
          if count > 0, let base = ptr.baseAddress {
            outputData.append(base, count: count)
          }
        }
      } catch {
        finished = true
        throw error
      }

      if !outputData.isEmpty {
        do {
          try await sink.write(data: outputData)
        } catch {
          finished = true
          throw error
        }
      }

      switch status {
      case .producedOutput, .needMoreOutputSpace:
        continue
      case .endOfStream:
        finished = true
        done = true
      }
    }
  }

  public func close() async throws {
    try beginOperation()
    defer { endOperation() }

    guard !closeAttempted else { throw IOError.streamClosed }

    closeAttempted = true
    finished = true
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

//
//  FormatStreamWriterDriver.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/18/26.
//

import Foundation
import SolidIO

/// Async driver that feeds a synchronous ``FormatStreamEncoder`` to a ``Sink``.
public final class FormatStreamWriterDriver<Encoder: FormatStreamEncoder>: FormatStreamWriter {

  private var encoder: Encoder
  private let sink: any Sink
  private let bufferSize: Int
  private var buffer: [UInt8]
  private var outputData = Data()
  private var finished = false

  public init(
    encoder: Encoder,
    sink: any Sink,
    bufferSize: Int = BufferedSink.segmentSize
  ) {
    self.encoder = encoder
    self.sink = sink
    self.bufferSize = bufferSize
    self.buffer = [UInt8](repeating: 0, count: bufferSize)
  }

  public var format: Format { encoder.format }

  public func write(_ event: ValueEvent) async throws {
    guard !finished else { throw IOError.streamClosed }

    var done = false
    while !done {
      var status: FormatStreamEncodeStatus = .producedOutput
      outputData.removeAll(keepingCapacity: true)

      try buffer.withUnsafeMutableBufferPointer { ptr in
        var out = OutputSpan<UInt8>(buffer: ptr, initializedCount: 0)
        status = try encoder.encode(event, output: &out)
        let count = out.finalize(for: ptr)
        if count > 0, let base = ptr.baseAddress {
          outputData.append(base, count: count)
        }
      }

      if !outputData.isEmpty {
        try await sink.write(data: outputData)
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

  public func finish() async throws {
    guard !finished else { throw IOError.streamClosed }

    var done = false
    while !done {
      var status: FormatStreamEncodeStatus = .producedOutput
      outputData.removeAll(keepingCapacity: true)

      try buffer.withUnsafeMutableBufferPointer { ptr in
        var out = OutputSpan<UInt8>(buffer: ptr, initializedCount: 0)
        status = try encoder.finish(output: &out)
        let count = out.finalize(for: ptr)
        if count > 0, let base = ptr.baseAddress {
          outputData.append(base, count: count)
        }
      }

      if !outputData.isEmpty {
        try await sink.write(data: outputData)
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
    try await sink.close()
  }
}

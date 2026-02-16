//
//  FormatStreamEncoder.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/18/26.
//

import Foundation

/// Status returned from a streaming encode operation.
public enum FormatStreamEncodeStatus: Sendable, Equatable {
  /// Produced output bytes (or filled the output span).
  case producedOutput
  /// Needs more output capacity to continue encoding.
  case needMoreOutputSpace
  /// End of stream reached.
  case endOfStream
}

/// Streaming encoder for a ``Format``.
public protocol FormatStreamEncoder {

  /// The format this encoder writes.
  var format: Format { get }

  /// Encode the next event into the provided output span.
  ///
  /// - Parameters:
  ///   - event: The event to encode.
  ///   - output: Output span for emitted bytes.
  /// - Returns: Status indicating progress or completion.
  /// - Throws: Error if the event cannot be encoded.
  mutating func encode(
    _ event: ValueEvent,
    output: inout OutputSpan<UInt8>
  ) throws -> FormatStreamEncodeStatus

  /// Finalize the stream, emitting any closing bytes.
  mutating func finish(
    output: inout OutputSpan<UInt8>
  ) throws -> FormatStreamEncodeStatus
}

/// Helper for encoding a stream of events into a `Data` buffer.
public struct FormatStreamEncoderBuffer<Encoder: FormatStreamEncoder> {

  public var encoder: Encoder
  public var bufferSize: Int

  public init(encoder: Encoder, bufferSize: Int = 1024) {
    self.encoder = encoder
    self.bufferSize = bufferSize
  }

  public mutating func encode(events: some Sequence<ValueEvent>) throws -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    for event in events {
      var done = false
      while !done {
        let status = try buffer.withUnsafeMutableBufferPointer { ptr -> FormatStreamEncodeStatus in
          var out = OutputSpan<UInt8>(buffer: ptr, initializedCount: 0)
          let status = try encoder.encode(event, output: &out)
          let count = out.finalize(for: ptr)
          if count > 0, let base = ptr.baseAddress {
            data.append(base, count: count)
          }
          return status
        }
        switch status {
        case .producedOutput:
          done = true
        case .needMoreOutputSpace:
          continue
        case .endOfStream:
          done = true
        }
      }
    }

    var finishing = false
    while !finishing {
      let status = try buffer.withUnsafeMutableBufferPointer { ptr -> FormatStreamEncodeStatus in
        var out = OutputSpan<UInt8>(buffer: ptr, initializedCount: 0)
        let status = try encoder.finish(output: &out)
        let count = out.finalize(for: ptr)
        if count > 0, let base = ptr.baseAddress {
          data.append(base, count: count)
        }
        return status
      }
      switch status {
      case .producedOutput, .needMoreOutputSpace:
        continue
      case .endOfStream:
        finishing = true
      }
    }

    return data
  }
}

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
    _ event: EmitEvent,
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

  public mutating func encode(events: some Sequence<EmitEvent>) throws -> Data {
    try encode { emit in
      for event in events {
        try emit(event)
      }
    }
  }

  public mutating func encode(
    _ produceEvents: (_ emit: (EmitEvent) throws -> Void) throws -> Void
  ) throws -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    func encodeEvent(_ event: EmitEvent) throws {
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

    try produceEvents { event in
      try encodeEvent(event)
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

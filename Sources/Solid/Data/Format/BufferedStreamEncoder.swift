//
//  BufferedStreamEncoder.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import Foundation

/// A generic ``FormatStreamEncoder`` that wraps a ``FormatEventWriter``,
/// managing the shared buffer infrastructure (buffering, draining, pending state).
///
/// Each format-specific encoder becomes a ``FormatEventWriter`` that owns only
/// its semantic state and writes bytes into a provided `inout Data` buffer.
/// `BufferedStreamEncoder` handles the `encode`/`finish`/`drainPending` logic
/// that was previously duplicated across all three format encoders.
public struct BufferedStreamEncoder<Writer: FormatEventWriter>: FormatStreamEncoder {

  public var writer: Writer

  private var buffer = Data()
  private var pendingOffset = 0
  private var pendingEvent = false
  private var finished = false

  public init(writer: Writer) {
    self.writer = writer
  }

  public var format: Format { writer.format }

  public mutating func encode(
    _ event: EmitEvent,
    output: inout OutputSpan<UInt8>
  ) throws -> FormatStreamEncodeStatus {
    if pendingEvent {
      let pendingStatus = drainPending(into: &output)
      if pendingStatus == .needMoreOutputSpace {
        return pendingStatus
      }
      pendingEvent = false
      return .producedOutput
    }

    let pendingStatus = drainPending(into: &output)
    if pendingStatus == .needMoreOutputSpace {
      return pendingStatus
    }

    try writer.writeEvent(event, into: &buffer)
    let status = drainPending(into: &output)
    if status == .needMoreOutputSpace {
      pendingEvent = true
    }
    return status
  }

  public mutating func finish(
    output: inout OutputSpan<UInt8>
  ) throws -> FormatStreamEncodeStatus {
    let pendingStatus = drainPending(into: &output)
    if pendingStatus == .needMoreOutputSpace {
      return pendingStatus
    }

    if finished {
      let finalStatus = drainPending(into: &output)
      return finalStatus == .needMoreOutputSpace ? finalStatus : .endOfStream
    }

    try writer.finishWriting(into: &buffer)
    finished = true

    let finalStatus = drainPending(into: &output)
    return finalStatus == .needMoreOutputSpace ? finalStatus : .endOfStream
  }

  private mutating func drainPending(
    into output: inout OutputSpan<UInt8>
  ) -> FormatStreamEncodeStatus {
    guard pendingOffset < buffer.count else {
      buffer.removeAll(keepingCapacity: true)
      pendingOffset = 0
      return .producedOutput
    }

    guard !output.isFull else { return .needMoreOutputSpace }

    let available = buffer.count - pendingOffset
    let outputRemaining = output.capacity - output.count
    let toCopy = min(available, outputRemaining)
    buffer.withUnsafeBytes { rawBuffer in
      let src = rawBuffer.baseAddress!.advanced(by: pendingOffset)
        .assumingMemoryBound(to: UInt8.self)
      output.withUnsafeMutableBufferPointer { destBuf, initializedCount in
        destBuf.baseAddress!.advanced(by: initializedCount)
          .initialize(from: src, count: toCopy)
        initializedCount += toCopy
      }
    }
    pendingOffset += toCopy

    if pendingOffset >= buffer.count {
      buffer.removeAll(keepingCapacity: true)
      pendingOffset = 0
      return .producedOutput
    }

    return .needMoreOutputSpace
  }
}

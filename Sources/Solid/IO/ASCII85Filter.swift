//
//  ASCII85Filter.swift
//  SolidIO
//
//  Created by Codex on 8/15/26.
//

import Foundation
import Synchronization

/// An incremental ASCII base-85 encoder.
public final class ASCII85Encoder: IncrementalFilter {

  private struct State: Sendable {
    var pending = Data()
    var column = 0
    var finished = false
  }

  private let state = Mutex(State())

  /// Creates an ASCII base-85 encoder.
  public init() {}

  /// Encodes complete four-byte tuples from the supplied input.
  public func process(input: Data) throws -> IncrementalFilterResult {
    try state.withLock { state in
      guard !state.finished else { throw StreamCodecError.invalidData }
      state.pending.append(input)
      var output = Data()

      while state.pending.count >= 4 {
        let tuple = Data(state.pending.prefix(4))
        state.pending.removeFirst(4)
        var column = state.column
        Self.appendEncoded(tuple, count: 4, to: &output, column: &column)
        state.column = column
      }

      return IncrementalFilterResult(
        output: output,
        consumedInput: input.count,
        progress: .needsInput
      )
    }
  }

  /// Emits a line break without ending the stream.
  public func flush() throws -> Data {
    try state.withLock { state in
      guard !state.finished else { throw StreamCodecError.invalidData }
      guard state.column > 0 else { return Data() }
      state.column = 0
      return Data([0x0A])
    }
  }

  /// Encodes a partial final tuple and emits `~>`.
  public func finish() throws -> Data? {
    state.withLock { state in
      guard !state.finished else { return nil }
      state.finished = true
      var output = Data()
      if !state.pending.isEmpty {
        let pending = state.pending
        var column = state.column
        Self.appendEncoded(
          pending,
          count: pending.count,
          to: &output,
          column: &column
        )
        state.column = column
      }
      var column = state.column
      Self.appendWrapped(Data([0x7E, 0x3E]), to: &output, column: &column)
      state.column = column
      state.pending.removeAll()
      return output
    }
  }

  private static func appendEncoded(
    _ input: Data,
    count: Int,
    to output: inout Data,
    column: inout Int
  ) {
    var value: UInt32 = 0
    for index in 0..<4 {
      let byte = index < count
        ? input[input.index(input.startIndex, offsetBy: index)]
        : 0
      value = (value << 8) | UInt32(byte)
    }

    if count == 4 && value == 0 {
      appendWrapped(Data([0x7A]), to: &output, column: &column)
      return
    }

    var encoded = [UInt8](repeating: 0, count: 5)
    for index in stride(from: 4, through: 0, by: -1) {
      encoded[index] = UInt8(value % 85) + 33
      value /= 85
    }
    appendWrapped(Data(encoded.prefix(count + 1)), to: &output, column: &column)
  }

  private static func appendWrapped(_ data: Data, to output: inout Data, column: inout Int) {
    for byte in data {
      if column == 80 {
        output.append(0x0A)
        column = 0
      }
      output.append(byte)
      column += 1
    }
  }

}

/// An incremental ASCII base-85 decoder.
public final class ASCII85Decoder: IncrementalFilter {

  private struct State: Sendable {
    var tuple: [UInt8] = []
    var sawTilde = false
    var finished = false
  }

  private let state = Mutex(State())

  /// Creates an ASCII base-85 decoder.
  public init() {}

  /// Decodes ASCII base-85 data through the `~>` end marker.
  public func process(input: Data) throws -> IncrementalFilterResult {
    try state.withLock { state in
      guard !state.finished else {
        return IncrementalFilterResult(output: Data(), consumedInput: 0, progress: .finished)
      }

      var output = Data()
      var consumed = 0

      for byte in input {
        consumed += 1
        if state.sawTilde {
          guard byte == 0x3E else { throw StreamCodecError.invalidData }
          try Self.finishTuple(&state.tuple, output: &output)
          state.sawTilde = false
          state.finished = true
          return IncrementalFilterResult(
            output: output,
            consumedInput: consumed,
            progress: .finished
          )
        }

        if Self.isWhitespace(byte) {
          continue
        }
        if byte == 0x7E {
          state.sawTilde = true
          continue
        }
        if byte == 0x7A {
          guard state.tuple.isEmpty else { throw StreamCodecError.invalidData }
          output.append(contentsOf: [0, 0, 0, 0])
          continue
        }
        guard byte >= 33 && byte <= 117 else { throw StreamCodecError.invalidData }
        state.tuple.append(byte - 33)
        if state.tuple.count == 5 {
          try Self.decodeTuple(state.tuple, byteCount: 4, output: &output)
          state.tuple.removeAll(keepingCapacity: true)
        }
      }

      return IncrementalFilterResult(
        output: output,
        consumedInput: consumed,
        progress: .needsInput
      )
    }
  }

  /// Rejects a physical end of source without the required `~>` marker.
  public func finish() throws -> Data? {
    try state.withLock { state in
      guard !state.finished else { return nil }
      throw StreamCodecError.truncatedData
    }
  }

  private static func finishTuple(_ tuple: inout [UInt8], output: inout Data) throws {
    guard tuple.count != 1 else { throw StreamCodecError.invalidData }
    guard !tuple.isEmpty else { return }
    let byteCount = tuple.count - 1
    tuple.append(contentsOf: repeatElement(84, count: 5 - tuple.count))
    try decodeTuple(tuple, byteCount: byteCount, output: &output)
    tuple.removeAll()
  }

  private static func decodeTuple(_ tuple: [UInt8], byteCount: Int, output: inout Data) throws {
    var value: UInt64 = 0
    for digit in tuple {
      value = value * 85 + UInt64(digit)
    }
    guard value <= UInt64(UInt32.max) else { throw StreamCodecError.invalidData }
    let decoded = UInt32(value)
    for shift in stride(from: 24, through: 0, by: -8).prefix(byteCount) {
      output.append(UInt8((decoded >> UInt32(shift)) & 0xFF))
    }
  }

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 0 || byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32
  }

}

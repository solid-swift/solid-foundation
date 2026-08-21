//
//  ASCIIHexFilter.swift
//  SolidIO
//
//  Created by Codex on 8/15/26.
//

import Foundation
import Synchronization

/// An incremental ASCII hexadecimal encoder.
public final class ASCIIHexEncoder: IncrementalFilter {

  private struct State: Sendable {
    var column = 0
    var finished = false
  }

  private let state = Mutex(State())

  /// Creates an ASCII hexadecimal encoder.
  public init() {}

  /// Encodes the supplied bytes as hexadecimal digits.
  public func process(input: Data) throws -> IncrementalFilterResult {
    try state.withLock { state in
      guard !state.finished else { throw StreamCodecError.invalidData }

      let digits = Array("0123456789abcdef".utf8)
      var output = Data()
      output.reserveCapacity(input.count * 2 + input.count / 40)

      for byte in input {
        if state.column == 80 {
          output.append(0x0A)
          state.column = 0
        }
        output.append(digits[Int(byte >> 4)])
        output.append(digits[Int(byte & 0x0F)])
        state.column += 2
      }

      return IncrementalFilterResult(
        output: output,
        consumedInput: input.count,
        progress: .needsInput
      )
    }
  }

  /// Emits a line break without ending the encoded stream.
  public func flush() throws -> Data {
    try state.withLock { state in
      guard !state.finished else { throw StreamCodecError.invalidData }
      guard state.column > 0 else { return Data() }
      state.column = 0
      return Data([0x0A])
    }
  }

  /// Emits the ASCII hexadecimal end marker.
  public func finish() throws -> Data? {
    state.withLock { state in
      guard !state.finished else { return nil }
      state.finished = true
      state.column = 0
      return Data([0x3E])
    }
  }

}

/// An incremental ASCII hexadecimal decoder.
public final class ASCIIHexDecoder: IncrementalFilter {

  private struct State: Sendable {
    var highNibble: UInt8?
    var finished = false
  }

  private let state = Mutex(State())

  /// Creates an ASCII hexadecimal decoder.
  public init() {}

  /// Decodes hexadecimal digits until an ASCII hexadecimal end marker.
  public func process(input: Data) throws -> IncrementalFilterResult {
    try state.withLock { state in
      guard !state.finished else {
        return IncrementalFilterResult(output: Data(), consumedInput: 0, progress: .finished)
      }

      var output = Data()
      var consumed = 0

      for byte in input {
        consumed += 1
        if byte == 0x3E {
          if let highNibble = state.highNibble {
            output.append(highNibble << 4)
            state.highNibble = nil
          }
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

        guard let nibble = Self.nibble(byte) else { throw StreamCodecError.invalidData }
        if let highNibble = state.highNibble {
          output.append((highNibble << 4) | nibble)
          state.highNibble = nil
        } else {
          state.highNibble = nibble
        }
      }

      return IncrementalFilterResult(
        output: output,
        consumedInput: consumed,
        progress: .needsInput
      )
    }
  }

  /// Finishes decoding at the physical end of the source.
  public func finish() throws -> Data? {
    state.withLock { state in
      guard !state.finished else { return nil }
      state.finished = true
      if let highNibble = state.highNibble {
        state.highNibble = nil
        return Data([highNibble << 4])
      }
      return Data()
    }
  }

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 0 || byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32
  }

  private static func nibble(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 48...57: byte - 48
    case 65...70: byte - 55
    case 97...102: byte - 87
    default: nil
    }
  }

}

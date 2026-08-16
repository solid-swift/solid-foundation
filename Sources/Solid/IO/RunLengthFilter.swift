//
//  RunLengthFilter.swift
//  SolidIO
//
//  Created by Codex on 8/15/26.
//

import Foundation
import Synchronization

/// An incremental PostScript run-length encoder.
public final class RunLengthEncoder: IncrementalFilter {

  private struct State: Sendable {
    var input = Data()
    var finished = false
  }

  private let recordSize: Int
  private let state = Mutex(State())

  /// Creates a run-length encoder.
  ///
  /// - Parameter recordSize: Maximum source record size. Zero treats the input as one record.
  public init(recordSize: Int = 0) throws {
    guard recordSize >= 0 else { throw StreamCodecError.invalidOption("recordSize") }
    self.recordSize = recordSize
  }

  /// Buffers input until finalization so runs never cross record boundaries.
  public func process(input: Data) throws -> IncrementalFilterResult {
    try state.withLock { state in
      guard !state.finished else { throw StreamCodecError.invalidData }
      state.input.append(input)
      return IncrementalFilterResult(
        output: Data(),
        consumedInput: input.count,
        progress: .needsInput
      )
    }
  }

  /// Emits all encoded records followed by the run-length end marker.
  public func finish() throws -> Data? {
    state.withLock { state in
      guard !state.finished else { return nil }
      state.finished = true
      var output = Data()
      let size = recordSize == 0 ? max(state.input.count, 1) : recordSize
      var start = 0
      while start < state.input.count {
        let end = min(start + size, state.input.count)
        Self.encodeRecord(Data(state.input[start..<end]), into: &output)
        start = end
      }
      output.append(128)
      state.input.removeAll()
      return output
    }
  }

  private static func encodeRecord(_ record: Data, into output: inout Data) {
    var index = 0
    while index < record.count {
      var runLength = 1
      while index + runLength < record.count,
            runLength < 128,
            record[index + runLength] == record[index]
      {
        runLength += 1
      }

      if runLength >= 3 {
        output.append(UInt8(257 - runLength))
        output.append(record[index])
        index += runLength
        continue
      }

      let literalStart = index
      index += runLength
      while index < record.count && index - literalStart < 128 {
        var nextRun = 1
        while index + nextRun < record.count,
              nextRun < 128,
              record[index + nextRun] == record[index]
        {
          nextRun += 1
        }
        if nextRun >= 3 { break }
        index += nextRun
      }
      let literalCount = index - literalStart
      output.append(UInt8(literalCount - 1))
      output.append(record[literalStart..<index])
    }
  }

}

/// An incremental PostScript run-length decoder.
public final class RunLengthDecoder: IncrementalFilter {

  private enum Pending: Sendable {
    case control
    case literal(remaining: Int)
    case repeatByte(count: Int)
  }

  private struct State: Sendable {
    var pending = Pending.control
    var finished = false
  }

  private let state = Mutex(State())

  /// Creates a run-length decoder.
  public init() {}

  /// Decodes run-length records through byte `128`.
  public func process(input: Data) throws -> IncrementalFilterResult {
    state.withLock { state in
      guard !state.finished else {
        return IncrementalFilterResult(output: Data(), consumedInput: 0, progress: .finished)
      }
      var output = Data()
      var index = 0

      while index < input.count {
        switch state.pending {
        case .control:
          let byte = input[index]
          index += 1
          if byte == 128 {
            state.finished = true
            return IncrementalFilterResult(
              output: output,
              consumedInput: index,
              progress: .finished
            )
          } else if byte <= 127 {
            state.pending = .literal(remaining: Int(byte) + 1)
          } else {
            state.pending = .repeatByte(count: 257 - Int(byte))
          }

        case .literal(let remaining):
          let count = min(remaining, input.count - index)
          output.append(input[index..<(index + count)])
          index += count
          state.pending = count == remaining ? .control : .literal(remaining: remaining - count)

        case .repeatByte(let count):
          output.append(contentsOf: repeatElement(input[index], count: count))
          index += 1
          state.pending = .control
        }
      }

      return IncrementalFilterResult(
        output: output,
        consumedInput: index,
        progress: .needsInput
      )
    }
  }

  /// Validates that the run-length end marker was present.
  public func finish() throws -> Data? {
    try state.withLock { state in
      guard !state.finished else { return nil }
      throw StreamCodecError.truncatedData
    }
  }

}

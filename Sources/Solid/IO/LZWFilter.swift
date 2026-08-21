//
//  LZWFilter.swift
//  SolidIO
//
//  Created by Codex on 8/15/26.
//

import Foundation
import Synchronization

/// Options shared by PostScript LZW encoding and decoding.
public struct LZWOptions: Equatable, Sendable {

  /// Controls whether code width grows one code early.
  public var earlyChange: Int

  /// Number of bits in each uncompressed data unit.
  public var unitLength: Int

  /// Whether codes and data units are packed least-significant bit first.
  public var lowBitFirst: Bool

  /// Creates LZW options.
  public init(earlyChange: Int = 1, unitLength: Int = 8, lowBitFirst: Bool = false) throws {
    guard earlyChange == 0 || earlyChange == 1 else {
      throw StreamCodecError.invalidOption("earlyChange")
    }
    guard (3...8).contains(unitLength) else {
      throw StreamCodecError.invalidOption("unitLength")
    }
    self.earlyChange = earlyChange
    self.unitLength = unitLength
    self.lowBitFirst = lowBitFirst
  }

}

/// An incremental LZW encoder using the PostScript code-table conventions.
public final class LZWEncoder: IncrementalFilter {

  private struct State: Sendable {
    var input: LZWInputBits
    var output: LZWOutputBits
    var dictionary: [[Int]: Int] = [:]
    var nextCode: Int
    var codeWidth: Int
    var phrase: [Int]?
    var started = false
    var finished = false
  }

  private let options: LZWOptions
  private let state: Mutex<State>

  /// Creates an LZW encoder.
  public init(options: LZWOptions = try! LZWOptions()) {
    self.options = options
    state = Mutex(
      State(
        input: LZWInputBits(lowBitFirst: options.lowBitFirst),
        output: LZWOutputBits(lowBitFirst: options.lowBitFirst),
        nextCode: (1 << options.unitLength) + 2,
        codeWidth: options.unitLength + 1
      )
    )
  }

  /// Buffers source units for deterministic final code packing.
  public func process(input: Data) throws -> IncrementalFilterResult {
    try state.withLock { state in
      guard !state.finished else { throw StreamCodecError.invalidData }
      Self.startIfNeeded(&state, options: options)
      state.input.append(input)
      while let symbol = state.input.read(width: options.unitLength) {
        Self.consume(symbol, state: &state, options: options)
      }
      return IncrementalFilterResult(
        output: state.output.drain(),
        consumedInput: input.count,
        progress: .needsInput
      )
    }
  }

  /// Emits the complete LZW stream, including clear and end-of-data codes.
  public func finish() throws -> Data? {
    state.withLock { state in
      guard !state.finished else { return nil }
      state.finished = true
      Self.startIfNeeded(&state, options: options)
      if let phrase = state.phrase {
        state.output.write(state.dictionary[phrase] ?? phrase[0], width: state.codeWidth)
      }
      state.output.write((1 << options.unitLength) + 1, width: state.codeWidth)
      return state.output.finish()
    }
  }

  private static func startIfNeeded(_ state: inout State, options: LZWOptions) {
    guard !state.started else { return }
    state.started = true
    let clearCode = 1 << options.unitLength
    state.output.write(clearCode, width: state.codeWidth)
  }

  private static func consume(_ symbol: Int, state: inout State, options: LZWOptions) {
    guard let phrase = state.phrase else {
      state.phrase = [symbol]
      return
    }
    let candidate = phrase + [symbol]
    if state.dictionary[candidate] != nil {
      state.phrase = candidate
      return
    }

    state.output.write(state.dictionary[phrase] ?? phrase[0], width: state.codeWidth)
    if state.nextCode < 4096 {
      state.dictionary[candidate] = state.nextCode
      state.nextCode += 1
      if state.codeWidth < 12,
         state.nextCode + options.earlyChange == 1 << state.codeWidth
      {
        state.codeWidth += 1
      }
    } else {
      state.output.write(1 << options.unitLength, width: state.codeWidth)
      state.dictionary.removeAll(keepingCapacity: true)
      state.nextCode = (1 << options.unitLength) + 2
      state.codeWidth = options.unitLength + 1
    }
    state.phrase = [symbol]
  }

}

/// An incremental LZW decoder that preserves bytes following end-of-data.
public final class LZWDecoder: IncrementalFilter {

  private struct State: Sendable {
    var input: LZWCodeBits
    var output: LZWOutputBits
    var prefixes = [Int](repeating: -1, count: 4096)
    var suffixes = [Int](repeating: 0, count: 4096)
    var expansion: [Int] = []
    var nextCode: Int
    var codeWidth: Int
    var previousCode: Int?
    var finished = false

    init(options: LZWOptions) {
      input = LZWCodeBits(lowBitFirst: options.lowBitFirst)
      output = LZWOutputBits(lowBitFirst: options.lowBitFirst)
      nextCode = (1 << options.unitLength) + 2
      codeWidth = options.unitLength + 1
      expansion.reserveCapacity(4096)
    }
  }

  private let options: LZWOptions
  private let state: Mutex<State>

  /// Creates an LZW decoder.
  public init(options: LZWOptions = try! LZWOptions()) {
    self.options = options
    state = Mutex(State(options: options))
  }

  /// Decodes complete codes while preserving partial code and dictionary state.
  public func process(input: Data) throws -> IncrementalFilterResult {
    try state.withLock { state in
      guard !state.finished else {
        return IncrementalFilterResult(output: Data(), consumedInput: 0, progress: .finished)
      }

      let clearCode = 1 << options.unitLength
      let endCode = clearCode + 1
      var consumed = 0

      while true {
        Self.increaseCodeWidthIfNeeded(&state, options: options)
        guard let code = state.input.read(width: state.codeWidth, from: input, consumed: &consumed)
        else {
          return IncrementalFilterResult(
            output: state.output.drain(),
            consumedInput: consumed,
            progress: .needsInput
          )
        }

        if code == clearCode {
          Self.resetDictionary(&state, options: options)
          continue
        }
        if code == endCode {
          state.finished = true
          return IncrementalFilterResult(
            output: state.output.finish(),
            consumedInput: consumed,
            progress: .finished
          )
        }

        let firstSymbol: Int
        if code < state.nextCode {
          firstSymbol = try Self.writeEntry(code, state: &state, options: options)
        } else if code == state.nextCode, let previousCode = state.previousCode {
          firstSymbol = try Self.writeEntry(previousCode, state: &state, options: options)
          state.output.write(firstSymbol, width: options.unitLength)
        } else {
          throw StreamCodecError.invalidData
        }

        if let previousCode = state.previousCode, state.nextCode < 4096 {
          state.prefixes[state.nextCode] = previousCode
          state.suffixes[state.nextCode] = firstSymbol
          state.nextCode += 1
        }
        state.previousCode = code
      }
    }
  }

  /// Rejects a physical source end without an LZW end-of-data code.
  public func finish() throws -> Data? {
    try state.withLock { state in
      guard !state.finished else { return nil }
      throw StreamCodecError.truncatedData
    }
  }

  private static func increaseCodeWidthIfNeeded(_ state: inout State, options: LZWOptions) {
    if state.previousCode != nil,
       state.codeWidth < 12,
       state.nextCode + options.earlyChange + 1 == 1 << state.codeWidth
    {
      state.codeWidth += 1
    }
  }

  private static func resetDictionary(_ state: inout State, options: LZWOptions) {
    state.nextCode = (1 << options.unitLength) + 2
    state.codeWidth = options.unitLength + 1
    state.previousCode = nil
  }

  private static func writeEntry(
    _ code: Int,
    state: inout State,
    options: LZWOptions
  ) throws -> Int {
    let clearCode = 1 << options.unitLength
    let firstDictionaryCode = clearCode + 2
    state.expansion.removeAll(keepingCapacity: true)

    var current = code
    while current >= clearCode {
      guard current >= firstDictionaryCode,
            current < state.nextCode,
            state.expansion.count < 4096
      else {
        throw StreamCodecError.invalidData
      }
      state.expansion.append(state.suffixes[current])
      current = state.prefixes[current]
    }
    guard current >= 0 else { throw StreamCodecError.invalidData }

    state.output.write(current, width: options.unitLength)
    for symbol in state.expansion.reversed() {
      state.output.write(symbol, width: options.unitLength)
    }
    return current
  }

}

private struct LZWCodeBits: Sendable {
  private var reservoir: UInt64 = 0
  private var bitCount = 0
  private let lowBitFirst: Bool

  init(lowBitFirst: Bool) { self.lowBitFirst = lowBitFirst }

  mutating func read(width: Int, from input: Data, consumed: inout Int) -> Int? {
    while bitCount < width {
      guard consumed < input.count else { return nil }
      let index = input.index(input.startIndex, offsetBy: consumed)
      let byte = UInt64(input[index])
      if lowBitFirst {
        reservoir |= byte << bitCount
      } else {
        reservoir = (reservoir << 8) | byte
      }
      bitCount += 8
      consumed += 1
    }

    let mask = (UInt64(1) << width) - 1
    let value: UInt64
    if lowBitFirst {
      value = reservoir & mask
      reservoir >>= width
      bitCount -= width
    } else {
      bitCount -= width
      value = (reservoir >> bitCount) & mask
      reservoir &= bitCount == 0 ? 0 : (UInt64(1) << bitCount) - 1
    }
    return Int(value)
  }
}

private struct LZWInputBits: Sendable {
  private var data = Data()
  private var bitOffset = 0
  private let lowBitFirst: Bool

  init(lowBitFirst: Bool) { self.lowBitFirst = lowBitFirst }

  mutating func append(_ input: Data) { data.append(input) }

  mutating func read(width: Int) -> Int? {
    guard bitOffset + width <= data.count * 8 else { return nil }
    var value = 0
    for index in 0..<width {
      let absolute = bitOffset + index
      let bitIndex = lowBitFirst ? absolute % 8 : 7 - absolute % 8
      let byteIndex = data.index(data.startIndex, offsetBy: absolute / 8)
      let bit = Int((data[byteIndex] >> bitIndex) & 1)
      if lowBitFirst { value |= bit << index } else { value = value << 1 | bit }
    }
    bitOffset += width
    let consumedBytes = bitOffset / 8
    if consumedBytes > 0 {
      data.removeFirst(consumedBytes)
      bitOffset -= consumedBytes * 8
    }
    return value
  }
}

private struct LZWOutputBits: Sendable {
  private var completed = Data()
  private var partial: UInt8 = 0
  private var bitCount = 0
  private let lowBitFirst: Bool

  init(lowBitFirst: Bool) { self.lowBitFirst = lowBitFirst }

  mutating func write(_ value: Int, width: Int) {
    for index in 0..<width {
      let source = lowBitFirst ? index : width - index - 1
      if value & (1 << source) != 0 {
        let target = lowBitFirst ? bitCount : 7 - bitCount
        partial |= 1 << target
      }
      bitCount += 1
      if bitCount == 8 {
        completed.append(partial)
        partial = 0
        bitCount = 0
      }
    }
  }

  mutating func drain() -> Data {
    let result = completed
    completed.removeAll(keepingCapacity: true)
    return result
  }

  mutating func finish() -> Data {
    if bitCount > 0 {
      completed.append(partial)
      partial = 0
      bitCount = 0
    }
    return drain()
  }
}

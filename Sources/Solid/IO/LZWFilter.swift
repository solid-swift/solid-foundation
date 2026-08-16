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
    var input = Data()
    var finished = false
  }

  private let options: LZWOptions
  private let state = Mutex(State())

  /// Creates an LZW encoder.
  public init(options: LZWOptions = try! LZWOptions()) {
    self.options = options
  }

  /// Buffers source units for deterministic final code packing.
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

  /// Emits the complete LZW stream, including clear and end-of-data codes.
  public func finish() throws -> Data? {
    state.withLock { state in
      guard !state.finished else { return nil }
      state.finished = true
      defer { state.input.removeAll() }
      return Self.encode(state.input, options: options)
    }
  }

  private static func encode(_ input: Data, options: LZWOptions) -> Data {
    let symbols = BitReader(data: input, lowBitFirst: options.lowBitFirst)
      .allUnits(width: options.unitLength)
    let clearCode = 1 << options.unitLength
    let endCode = clearCode + 1
    var writer = BitWriter(lowBitFirst: options.lowBitFirst)
    var dictionary: [[Int]: Int] = [:]
    var nextCode = endCode + 1
    var codeWidth = options.unitLength + 1

    func reset() {
      dictionary.removeAll(keepingCapacity: true)
      nextCode = endCode + 1
      codeWidth = options.unitLength + 1
    }

    writer.write(clearCode, width: codeWidth)
    guard var phrase = symbols.first.map({ [$0] }) else {
      writer.write(endCode, width: codeWidth)
      return writer.finish()
    }

    for symbol in symbols.dropFirst() {
      let candidate = phrase + [symbol]
      if let _ = dictionary[candidate] {
        phrase = candidate
        continue
      }

      writer.write(dictionary[phrase] ?? phrase[0], width: codeWidth)
      if nextCode < 4096 {
        dictionary[candidate] = nextCode
        nextCode += 1
        if codeWidth < 12 && nextCode + options.earlyChange == 1 << codeWidth {
          codeWidth += 1
        }
      } else {
        writer.write(clearCode, width: codeWidth)
        reset()
      }
      phrase = [symbol]
    }

    writer.write(dictionary[phrase] ?? phrase[0], width: codeWidth)
    writer.write(endCode, width: codeWidth)
    return writer.finish()
  }

}

/// An incremental LZW decoder that preserves bytes following end-of-data.
public final class LZWDecoder: IncrementalFilter {

  private struct State: Sendable {
    var input = Data()
    var finished = false
  }

  private let options: LZWOptions
  private let state = Mutex(State())

  /// Creates an LZW decoder.
  public init(options: LZWOptions = try! LZWOptions()) {
    self.options = options
  }

  /// Decodes when the accumulated input contains an end-of-data code.
  public func process(input: Data) throws -> IncrementalFilterResult {
    try state.withLock { state in
      guard !state.finished else {
        return IncrementalFilterResult(output: Data(), consumedInput: 0, progress: .finished)
      }

      let previousCount = state.input.count
      var combined = state.input
      combined.append(input)
      guard let decoded = try Self.decode(combined, options: options) else {
        state.input = combined
        return IncrementalFilterResult(
          output: Data(),
          consumedInput: input.count,
          progress: .needsInput
        )
      }

      state.finished = true
      state.input.removeAll()
      return IncrementalFilterResult(
        output: decoded.output,
        consumedInput: max(0, decoded.consumedBytes - previousCount),
        progress: .finished
      )
    }
  }

  /// Rejects a physical source end without an LZW end-of-data code.
  public func finish() throws -> Data? {
    try state.withLock { state in
      guard !state.finished else { return nil }
      throw StreamCodecError.truncatedData
    }
  }

  private static func decode(
    _ input: Data,
    options: LZWOptions
  ) throws -> (output: Data, consumedBytes: Int)? {
    let clearCode = 1 << options.unitLength
    let endCode = clearCode + 1
    var reader = BitReader(data: input, lowBitFirst: options.lowBitFirst)
    var writer = BitWriter(lowBitFirst: options.lowBitFirst)
    var dictionary: [Int: [Int]] = [:]
    var nextCode = endCode + 1
    var codeWidth = options.unitLength + 1
    var previous: [Int]?

    func reset() {
      dictionary.removeAll(keepingCapacity: true)
      nextCode = endCode + 1
      codeWidth = options.unitLength + 1
      previous = nil
    }

    while true {
      if previous != nil,
         codeWidth < 12,
         nextCode + options.earlyChange + 1 == 1 << codeWidth
      {
        codeWidth += 1
      }
      guard let code = reader.read(width: codeWidth) else { return nil }
      if code == clearCode {
        reset()
        continue
      }
      if code == endCode {
        return (writer.finish(), reader.consumedBytes)
      }

      let entry: [Int]
      if code < clearCode {
        entry = [code]
      } else if let known = dictionary[code] {
        entry = known
      } else if code == nextCode, let previous {
        entry = previous + [previous[0]]
      } else {
        throw StreamCodecError.invalidData
      }

      for symbol in entry {
        writer.write(symbol, width: options.unitLength)
      }

      if let previous, nextCode < 4096 {
        dictionary[nextCode] = previous + [entry[0]]
        nextCode += 1
      }
      previous = entry
    }
  }

}

private struct BitReader {

  let data: Data
  let lowBitFirst: Bool
  private(set) var bitOffset = 0

  var consumedBytes: Int {
    (bitOffset + 7) / 8
  }

  mutating func read(width: Int) -> Int? {
    guard bitOffset + width <= data.count * 8 else { return nil }
    var value = 0
    for index in 0..<width {
      let absolute = bitOffset + index
      let byte = data[data.index(data.startIndex, offsetBy: absolute / 8)]
      let bitIndex = lowBitFirst ? absolute % 8 : 7 - absolute % 8
      let bit = Int((byte >> bitIndex) & 1)
      if lowBitFirst {
        value |= bit << index
      } else {
        value = (value << 1) | bit
      }
    }
    bitOffset += width
    return value
  }

  func allUnits(width: Int) -> [Int] {
    var copy = self
    var values: [Int] = []
    while let value = copy.read(width: width) {
      values.append(value)
    }
    return values
  }

}

private struct BitWriter {

  let lowBitFirst: Bool
  private var bytes: [UInt8] = []
  private var bitOffset = 0

  init(lowBitFirst: Bool) {
    self.lowBitFirst = lowBitFirst
  }

  mutating func write(_ value: Int, width: Int) {
    for index in 0..<width {
      if bitOffset % 8 == 0 {
        bytes.append(0)
      }
      let sourceBit = lowBitFirst ? index : width - index - 1
      if value & (1 << sourceBit) != 0 {
        let targetBit = lowBitFirst ? bitOffset % 8 : 7 - bitOffset % 8
        bytes[bytes.count - 1] |= 1 << targetBit
      }
      bitOffset += 1
    }
  }

  mutating func finish() -> Data {
    Data(bytes)
  }

}

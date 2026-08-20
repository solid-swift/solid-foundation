import Foundation

enum CCITTFaxCodec {

  struct Decoded {
    let data: Data
    let consumedBytes: Int
  }

  static func encode(_ data: Data, options: CCITTFaxOptions) throws -> Data {
    let rowBytes = (options.columns + 7) / 8
    let (expectedBytes, overflow) = rowBytes.multipliedReportingOverflow(by: max(options.rows, 1))
    guard !overflow, expectedBytes <= 512 * 1024 * 1024, data.count <= 512 * 1024 * 1024 else {
      throw StreamCodecError.limitExceeded
    }
    guard data.count > 0, data.count.isMultiple(of: rowBytes) else {
      throw StreamCodecError.truncatedData
    }
    let rowCount = data.count / rowBytes
    guard options.rows == 0 || options.rows == rowCount else {
      throw StreamCodecError.truncatedData
    }

    var writer = FaxBitWriter()
    var reference = [Bool](repeating: false, count: options.columns)
    for rowIndex in 0..<rowCount {
      let row = unpackRow(data, row: rowIndex, rowBytes: rowBytes, options: options)
      if options.k < 0 {
        encode2D(row, reference: reference, writer: &writer)
      } else if options.k == 0 {
        if options.endOfLine { writer.write(FaxCodes.endOfLine) }
        encode1D(row, writer: &writer)
      } else {
        writer.write(FaxCodes.endOfLine)
        let isOneDimensional = rowIndex.isMultiple(of: options.k + 1)
        writer.writeBit(isOneDimensional)
        if isOneDimensional {
          encode1D(row, writer: &writer)
        } else {
          encode2D(row, reference: reference, writer: &writer)
        }
      }
      if options.encodedByteAlign { writer.align() }
      reference = row
    }

    if options.endOfBlock {
      let count = options.k < 0 ? 2 : 6
      for _ in 0..<count { writer.write(FaxCodes.endOfLine) }
    }
    return writer.finish()
  }

  static func decode(_ data: Data, options: CCITTFaxOptions) throws -> Decoded {
    var reader = FaxBitReader(data)
    let rowBytes = (options.columns + 7) / 8
    let (expectedBytes, overflow) = rowBytes.multipliedReportingOverflow(by: max(options.rows, 1))
    guard !overflow, expectedBytes <= 512 * 1024 * 1024, data.count <= 512 * 1024 * 1024 else {
      throw StreamCodecError.limitExceeded
    }
    var output = Data()
    if options.rows > 0 { output.reserveCapacity(rowBytes * options.rows) }
    var reference = [Bool](repeating: false, count: options.columns)
    var rowIndex = 0
    var damagedRows = 0

    while options.rows == 0 || rowIndex < options.rows {
      if options.encodedByteAlign, rowIndex > 0 { reader.align() }
      if options.endOfBlock, reader.matchesEndOfBlock(k: options.k) { break }

      let row: [Bool]
      do {
        if options.k < 0 {
          row = try decode2D(reference: reference, columns: options.columns, reader: &reader)
        } else if options.k == 0 {
          if options.endOfLine { try reader.readEndOfLine() }
          row = try decode1D(columns: options.columns, reader: &reader)
        } else {
          try reader.readEndOfLine()
          row = try reader.readBit()
            ? decode1D(columns: options.columns, reader: &reader)
            : decode2D(reference: reference, columns: options.columns, reader: &reader)
        }
      } catch {
        guard options.k >= 0,
              damagedRows < options.damagedRowsBeforeError,
              reader.seekToEndOfLine()
        else {
          throw error
        }
        damagedRows += 1
        appendRow(reference, blackIs1: options.blackIs1, to: &output)
        rowIndex += 1
        continue
      }

      appendRow(row, blackIs1: options.blackIs1, to: &output)
      reference = row
      rowIndex += 1
    }

    guard options.rows == 0 ? rowIndex > 0 : rowIndex == options.rows else {
      throw StreamCodecError.truncatedData
    }
    if options.endOfBlock {
      try reader.readEndOfBlock(k: options.k)
    }
    return Decoded(data: output, consumedBytes: reader.consumedBytes)
  }

  private static func encode1D(_ row: [Bool], writer: inout FaxBitWriter) {
    var column = 0
    var black = false
    repeat {
      let end = nextChange(in: row, from: column, color: black)
      writeRun(end - column, black: black, writer: &writer)
      column = end
      black.toggle()
    } while column < row.count
  }

  private static func decode1D(
    columns: Int,
    reader: inout FaxBitReader
  ) throws -> [Bool] {
    var row = [Bool](repeating: false, count: columns)
    var column = 0
    var black = false
    repeat {
      let run = try readRun(black: black, reader: &reader)
      guard run >= 0, column + run <= columns else { throw StreamCodecError.invalidData }
      if black, run > 0 { row.replaceSubrange(column..<(column + run), with: repeatElement(true, count: run)) }
      column += run
      black.toggle()
    } while column < columns
    return row
  }

  private static func encode2D(
    _ row: [Bool],
    reference: [Bool],
    writer: inout FaxBitWriter
  ) {
    var a0 = 0
    var black = false
    while a0 < row.count {
      let a1 = nextChange(in: row, from: a0, color: black)
      let b1 = referenceChange(in: reference, from: a0, oppositeTo: black)
      let b2 = nextChange(in: reference, from: b1, color: !black)
      if b2 < a1 {
        writer.write(FaxCodes.pass)
        a0 = b2
      } else {
        let delta = a1 - b1
        if let vertical = FaxCodes.vertical[delta] {
          writer.write(vertical)
          a0 = a1
          black.toggle()
        } else {
          writer.write(FaxCodes.horizontal)
          let a2 = nextChange(in: row, from: a1, color: !black)
          writeRun(a1 - a0, black: black, writer: &writer)
          writeRun(a2 - a1, black: !black, writer: &writer)
          a0 = a2
        }
      }
    }
  }

  private static func decode2D(
    reference: [Bool],
    columns: Int,
    reader: inout FaxBitReader
  ) throws -> [Bool] {
    var row = [Bool](repeating: false, count: columns)
    var a0 = 0
    var black = false
    while a0 < columns {
      let mode = try reader.read2DMode()
      switch mode {
      case .pass:
        let b1 = referenceChange(in: reference, from: a0, oppositeTo: black)
        let b2 = nextChange(in: reference, from: b1, color: !black)
        guard b2 > a0, b2 <= columns else { throw StreamCodecError.invalidData }
        if black { row.replaceSubrange(a0..<b2, with: repeatElement(true, count: b2 - a0)) }
        a0 = b2

      case .horizontal:
        let first = try readRun(black: black, reader: &reader)
        let second = try readRun(black: !black, reader: &reader)
        guard first >= 0, second >= 0, a0 + first + second <= columns else {
          throw StreamCodecError.invalidData
        }
        if black, first > 0 {
          row.replaceSubrange(a0..<(a0 + first), with: repeatElement(true, count: first))
        }
        if !black, second > 0 {
          let start = a0 + first
          row.replaceSubrange(start..<(start + second), with: repeatElement(true, count: second))
        }
        a0 += first + second

      case .vertical(let delta):
        let b1 = referenceChange(in: reference, from: a0, oppositeTo: black)
        let a1 = b1 + delta
        guard a1 >= a0, a1 <= columns else { throw StreamCodecError.invalidData }
        if black, a1 > a0 {
          row.replaceSubrange(a0..<a1, with: repeatElement(true, count: a1 - a0))
        }
        a0 = a1
        black.toggle()
      }
    }
    return row
  }

  private static func writeRun(_ length: Int, black: Bool, writer: inout FaxBitWriter) {
    var remaining = length
    let makeup = black ? FaxCodes.blackMakeup : FaxCodes.whiteMakeup
    while remaining >= 64 {
      let value = min(2560, remaining / 64 * 64)
      writer.write(makeup[value]!)
      remaining -= value
    }
    writer.write((black ? FaxCodes.blackTerminating : FaxCodes.whiteTerminating)[remaining])
  }

  private static func readRun(black: Bool, reader: inout FaxBitReader) throws -> Int {
    let terminating = black ? FaxCodes.blackTerminatingLookup : FaxCodes.whiteTerminatingLookup
    let makeup = black ? FaxCodes.blackMakeupLookup : FaxCodes.whiteMakeupLookup
    var total = 0
    while true {
      var bits = 0
      for length in 1...13 {
        bits = bits << 1 | (try reader.readBit() ? 1 : 0)
        let key = FaxCodeKey(bits: bits, length: length)
        if let run = terminating[key] { return total + run }
        if let run = makeup[key] {
          total += run
          break
        }
        if length == 13 { throw StreamCodecError.invalidData }
      }
    }
  }

  private static func nextChange(in row: [Bool], from start: Int, color: Bool) -> Int {
    var index = start
    while index < row.count, row[index] == color { index += 1 }
    return index
  }

  private static func referenceChange(
    in row: [Bool],
    from start: Int,
    oppositeTo color: Bool
  ) -> Int {
    var previous = start == 0 ? false : row[min(start - 1, row.count - 1)]
    for index in start..<row.count where row[index] != previous {
      previous = row[index]
      if previous != color { return index }
    }
    return row.count
  }

  private static func unpackRow(
    _ data: Data,
    row: Int,
    rowBytes: Int,
    options: CCITTFaxOptions
  ) -> [Bool] {
    (0..<options.columns).map { column in
      let bit = data[row * rowBytes + column / 8] & (1 << (7 - column % 8)) != 0
      return options.blackIs1 ? bit : !bit
    }
  }

  private static func appendRow(_ row: [Bool], blackIs1: Bool, to output: inout Data) {
    var bytes = [UInt8](repeating: 0, count: (row.count + 7) / 8)
    for (column, black) in row.enumerated() {
      let bit = blackIs1 ? black : !black
      if bit { bytes[column / 8] |= 1 << (7 - column % 8) }
    }
    output.append(contentsOf: bytes)
  }

}

private struct FaxBitWriter {
  private var bytes: [UInt8] = []
  private var current: UInt8 = 0
  private var bitCount = 0

  mutating func write(_ code: FaxCode) {
    for shift in stride(from: code.length - 1, through: 0, by: -1) {
      writeBit(code.bits & (1 << shift) != 0)
    }
  }

  mutating func writeBit(_ bit: Bool) {
    current = current << 1 | (bit ? 1 : 0)
    bitCount += 1
    if bitCount == 8 {
      bytes.append(current)
      current = 0
      bitCount = 0
    }
  }

  mutating func align() {
    while bitCount != 0 { writeBit(false) }
  }

  consuming func finish() -> Data {
    var writer = self
    writer.align()
    return Data(writer.bytes)
  }
}

private struct FaxBitReader {
  enum Mode { case pass, horizontal, vertical(Int) }

  private let data: Data
  private(set) var bitOffset = 0

  init(_ data: Data) { self.data = data }

  var consumedBytes: Int { (bitOffset + 7) / 8 }

  mutating func readBit() throws -> Bool {
    guard bitOffset < data.count * 8 else { throw StreamCodecError.truncatedData }
    let value = data[bitOffset / 8] & (1 << (7 - bitOffset % 8)) != 0
    bitOffset += 1
    return value
  }

  mutating func align() {
    bitOffset = min(data.count * 8, (bitOffset + 7) / 8 * 8)
  }

  mutating func readEndOfLine() throws {
    for _ in 0..<11 where try readBit() { throw StreamCodecError.invalidData }
    guard try readBit() else { throw StreamCodecError.invalidData }
  }

  mutating func readEndOfBlock(k: Int) throws {
    let count = k < 0 ? 2 : 6
    for _ in 0..<count { try readEndOfLine() }
  }

  func matchesEndOfBlock(k: Int) -> Bool {
    var copy = self
    do {
      try copy.readEndOfBlock(k: k)
      return true
    } catch {
      return false
    }
  }

  mutating func seekToEndOfLine() -> Bool {
    var zeros = 0
    while bitOffset < data.count * 8 {
      guard let bit = try? readBit() else { return false }
      if bit {
        if zeros >= 11 { return true }
        zeros = 0
      } else {
        zeros += 1
      }
    }
    return false
  }

  mutating func read2DMode() throws -> Mode {
    var bits = 0
    for length in 1...7 {
      bits = bits << 1 | (try readBit() ? 1 : 0)
      if let mode = FaxCodes.twoDimensional[FaxCodeKey(bits: bits, length: length)] {
        return mode
      }
    }
    throw StreamCodecError.invalidData
  }
}

private struct FaxCode: Sendable {
  let bits: Int
  let length: Int

  init(_ value: String) {
    bits = value.reduce(0) { $0 << 1 | ($1 == "1" ? 1 : 0) }
    length = value.count
  }
}

private struct FaxCodeKey: Hashable {
  let bits: Int
  let length: Int
}

private enum FaxCodes {
  static let endOfLine = FaxCode("000000000001")
  static let pass = FaxCode("0001")
  static let horizontal = FaxCode("001")
  static let vertical = [
    -3: FaxCode("0000010"), -2: FaxCode("000010"), -1: FaxCode("010"),
    0: FaxCode("1"), 1: FaxCode("011"), 2: FaxCode("000011"), 3: FaxCode("0000011"),
  ]
  static let twoDimensional: [FaxCodeKey: FaxBitReader.Mode] = {
    var result: [FaxCodeKey: FaxBitReader.Mode] = [
      key(pass): .pass,
      key(horizontal): .horizontal,
    ]
    for (delta, code) in vertical { result[key(code)] = .vertical(delta) }
    return result
  }()

  static let whiteTerminating = codes([
    "00110101", "000111", "0111", "1000", "1011", "1100", "1110", "1111",
    "10011", "10100", "00111", "01000", "001000", "000011", "110100", "110101",
    "101010", "101011", "0100111", "0001100", "0001000", "0010111", "0000011", "0000100",
    "0101000", "0101011", "0010011", "0100100", "0011000", "00000010", "00000011", "00011010",
    "00011011", "00010010", "00010011", "00010100", "00010101", "00010110", "00010111", "00101000",
    "00101001", "00101010", "00101011", "00101100", "00101101", "00000100", "00000101", "00001010",
    "00001011", "01010010", "01010011", "01010100", "01010101", "00100100", "00100101", "01011000",
    "01011001", "01011010", "01011011", "01001010", "01001011", "00110010", "00110011", "00110100",
  ])
  static let blackTerminating = codes([
    "0000110111", "010", "11", "10", "011", "0011", "0010", "00011",
    "000101", "000100", "0000100", "0000101", "0000111", "00000100", "00000111", "000011000",
    "0000010111", "0000011000", "0000001000", "00001100111", "00001101000", "00001101100", "00000110111", "00000101000",
    "00000010111", "00000011000", "000011001010", "000011001011", "000011001100", "000011001101", "000001101000", "000001101001",
    "000001101010", "000001101011", "000011010010", "000011010011", "000011010100", "000011010101", "000011010110", "000011010111",
    "000001101100", "000001101101", "000011011010", "000011011011", "000001010100", "000001010101", "000001010110", "000001010111",
    "000001100100", "000001100101", "000001010010", "000001010011", "000000100100", "000000110111", "000000111000", "000000100111",
    "000000101000", "000001011000", "000001011001", "000000101011", "000000101100", "000001011010", "000001100110", "000001100111",
  ])
  private static let whiteBaseMakeup = makeup([
    64: "11011", 128: "10010", 192: "010111", 256: "0110111",
    320: "00110110", 384: "00110111", 448: "01100100", 512: "01100101",
    576: "01101000", 640: "01100111", 704: "011001100", 768: "011001101",
    832: "011010010", 896: "011010011", 960: "011010100", 1024: "011010101",
    1088: "011010110", 1152: "011010111", 1216: "011011000", 1280: "011011001",
    1344: "011011010", 1408: "011011011", 1472: "010011000", 1536: "010011001",
    1600: "010011010", 1664: "011000", 1728: "010011011",
  ])
  private static let blackBaseMakeup = makeup([
    64: "0000001111", 128: "000011001000", 192: "000011001001", 256: "000001011011",
    320: "000000110011", 384: "000000110100", 448: "000000110101", 512: "0000001101100",
    576: "0000001101101", 640: "0000001001010", 704: "0000001001011", 768: "0000001001100",
    832: "0000001001101", 896: "0000001110010", 960: "0000001110011", 1024: "0000001110100",
    1088: "0000001110101", 1152: "0000001110110", 1216: "0000001110111", 1280: "0000001010010",
    1344: "0000001010011", 1408: "0000001010100", 1472: "0000001010101", 1536: "0000001011010",
    1600: "0000001011011", 1664: "0000001100100", 1728: "0000001100101",
  ])
  private static let additionalMakeup = makeup([
    1792: "00000001000", 1856: "00000001100", 1920: "00000001101", 1984: "000000010010",
    2048: "000000010011", 2112: "000000010100", 2176: "000000010101", 2240: "000000010110",
    2304: "000000010111", 2368: "000000011100", 2432: "000000011101", 2496: "000000011110",
    2560: "000000011111",
  ])
  static let whiteMakeup = whiteBaseMakeup.merging(additionalMakeup) { first, _ in first }
  static let blackMakeup = blackBaseMakeup.merging(additionalMakeup) { first, _ in first }

  static let whiteTerminatingLookup = lookup(whiteTerminating)
  static let blackTerminatingLookup = lookup(blackTerminating)
  static let whiteMakeupLookup = lookup(whiteMakeup)
  static let blackMakeupLookup = lookup(blackMakeup)

  private static func codes(_ values: [String]) -> [FaxCode] { values.map(FaxCode.init) }
  private static func makeup(_ values: [Int: String]) -> [Int: FaxCode] {
    values.mapValues(FaxCode.init)
  }
  private static func lookup(_ values: [FaxCode]) -> [FaxCodeKey: Int] {
    Dictionary(uniqueKeysWithValues: values.enumerated().map { (key($0.element), $0.offset) })
  }
  private static func lookup(_ values: [Int: FaxCode]) -> [FaxCodeKey: Int] {
    Dictionary(uniqueKeysWithValues: values.map { (key($0.value), $0.key) })
  }
  private static func key(_ code: FaxCode) -> FaxCodeKey {
    FaxCodeKey(bits: code.bits, length: code.length)
  }
}

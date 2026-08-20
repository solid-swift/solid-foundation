struct JPEGHuffmanKey: Hashable {
  let tableClass: JPEGHuffmanTableClass
  let identifier: UInt8
}

struct JPEGHuffmanCodec {

  private struct Entry {
    let code: UInt16
    let length: Int
    let symbol: UInt8
  }

  private let entries: [Entry]
  private let encoding: [UInt8: (code: UInt16, length: Int)]

  init(table: JPEGHuffmanTable) throws {
    var entries: [Entry] = []
    var encoding: [UInt8: (UInt16, Int)] = [:]
    var code: UInt16 = 0
    var symbolIndex = 0
    for length in 1...16 {
      for _ in 0..<Int(table.codeCounts[length - 1]) {
        guard symbolIndex < table.symbols.count else { throw JPEGError.invalidData }
        let symbol = table.symbols[symbolIndex]
        entries.append(Entry(code: code, length: length, symbol: symbol))
        encoding[symbol] = (code, length)
        code += 1
        symbolIndex += 1
      }
      if length != 16 { code <<= 1 }
    }
    self.entries = entries
    self.encoding = encoding
  }

  func decode(from reader: inout JPEGEntropyBitReader) throws -> UInt8 {
    var code: UInt16 = 0
    for length in 1...16 {
      code = code << 1 | UInt16(try reader.readBit())
      if let entry = entries.first(where: { $0.length == length && $0.code == code }) {
        return entry.symbol
      }
    }
    throw JPEGError.invalidData
  }

  func decode(from reader: inout JPEGIncrementalEntropyReader) throws -> UInt8 {
    var code: UInt16 = 0
    for length in 1...16 {
      code = code << 1 | UInt16(try reader.readBit())
      if let entry = entries.first(where: { $0.length == length && $0.code == code }) {
        return entry.symbol
      }
    }
    throw JPEGError.invalidData
  }

  func encode(symbol: UInt8, to writer: inout JPEGEntropyBitWriter) throws {
    guard let entry = encoding[symbol] else { throw JPEGError.invalidData }
    try writer.append(value: UInt32(entry.code), count: entry.length)
  }

}

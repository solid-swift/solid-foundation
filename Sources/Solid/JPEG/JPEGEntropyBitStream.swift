struct JPEGEntropyBitReader {

  private let bytes: [UInt8]
  private var offset = 0
  private var currentByte: UInt8 = 0
  private var remainingBits = 0

  init(bytes: [UInt8]) {
    self.bytes = bytes
  }

  mutating func readBit() throws -> UInt8 {
    if remainingBits == 0 {
      currentByte = try readEntropyByte()
      remainingBits = 8
    }
    remainingBits -= 1
    return currentByte >> remainingBits & 1
  }

  mutating func readBits(count: Int) throws -> Int {
    guard (0...16).contains(count) else { throw JPEGError.invalidData }
    var value = 0
    for _ in 0..<count { value = value << 1 | Int(try readBit()) }
    return value
  }

  mutating func consumeRestart(_ expected: UInt8) throws {
    remainingBits = 0
    guard offset < bytes.count, bytes[offset] == 0xFF else { throw JPEGError.invalidData }
    while offset < bytes.count, bytes[offset] == 0xFF { offset += 1 }
    guard offset < bytes.count, bytes[offset] == 0xD0 + expected else {
      throw JPEGError.invalidData
    }
    offset += 1
  }

  private mutating func readEntropyByte() throws -> UInt8 {
    guard offset < bytes.count else { throw JPEGError.truncatedData }
    let byte = bytes[offset]
    offset += 1
    guard byte == 0xFF else { return byte }
    guard offset < bytes.count else { throw JPEGError.truncatedData }
    let escaped = bytes[offset]
    offset += 1
    guard escaped == 0 else { throw JPEGError.invalidData }
    return 0xFF
  }

}

struct JPEGEntropyBitWriter {

  private(set) var bytes: [UInt8] = []
  private var accumulator: UInt8 = 0
  private var bitCount = 0
  private let maximumBytes: Int

  init(maximumBytes: Int) {
    self.maximumBytes = maximumBytes
  }

  mutating func append(value: UInt32, count: Int) throws {
    guard (0...24).contains(count) else { throw JPEGError.invalidData }
    for shift in (0..<count).reversed() {
      accumulator = accumulator << 1 | UInt8(value >> shift & 1)
      bitCount += 1
      if bitCount == 8 { try emitAccumulator() }
    }
  }

  mutating func emitRestart(_ index: UInt8) throws {
    try alignWithOnes()
    try reserve(2)
    bytes.append(0xFF)
    bytes.append(0xD0 + index)
  }

  mutating func finish() throws -> [UInt8] {
    try alignWithOnes()
    return drainBytes()
  }

  mutating func drainBytes() -> [UInt8] {
    let result = bytes
    bytes.removeAll(keepingCapacity: true)
    return result
  }

  private mutating func alignWithOnes() throws {
    while bitCount != 0 { try append(value: 1, count: 1) }
  }

  private mutating func emitAccumulator() throws {
    try reserve(accumulator == 0xFF ? 2 : 1)
    bytes.append(accumulator)
    if accumulator == 0xFF { bytes.append(0) }
    accumulator = 0
    bitCount = 0
  }

  private func reserve(_ count: Int) throws {
    guard count <= maximumBytes - bytes.count else { throw JPEGError.limitExceeded }
  }

}

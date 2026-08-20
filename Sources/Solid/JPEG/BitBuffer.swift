struct BitReader {

  private let bytes: [UInt8]
  private(set) var bitOffset = 0

  init(bytes: [UInt8]) {
    self.bytes = bytes
  }

  mutating func readBit() throws -> UInt8 {
    guard bitOffset < bytes.count * 8 else { throw JPEGError.truncatedData }
    let byte = bytes[bitOffset / 8]
    let bit = byte >> (7 - bitOffset % 8) & 1
    bitOffset += 1
    return bit
  }

  mutating func readBits(count: Int) throws -> UInt32 {
    guard (0...24).contains(count) else { throw JPEGError.invalidConfiguration("bitCount") }
    var value: UInt32 = 0
    for _ in 0..<count { value = value << 1 | UInt32(try readBit()) }
    return value
  }

}

struct BitWriter {

  private(set) var bytes: [UInt8] = []
  private var accumulator: UInt8 = 0
  private var count = 0
  private let maximumBytes: Int

  init(maximumBytes: Int) {
    self.maximumBytes = maximumBytes
  }

  mutating func append(value: UInt32, count: Int) throws {
    guard (0...24).contains(count) else { throw JPEGError.invalidConfiguration("bitCount") }
    for shift in (0..<count).reversed() {
      accumulator = accumulator << 1 | UInt8(value >> shift & 1)
      self.count += 1
      if self.count == 8 { try flushByte() }
    }
  }

  mutating func finish(paddingBit: UInt8 = 1) throws -> [UInt8] {
    guard paddingBit < 2 else { throw JPEGError.invalidConfiguration("paddingBit") }
    while count != 0 { try append(value: UInt32(paddingBit), count: 1) }
    return bytes
  }

  private mutating func flushByte() throws {
    guard bytes.count < maximumBytes else { throw JPEGError.limitExceeded }
    bytes.append(accumulator)
    accumulator = 0
    count = 0
  }

}

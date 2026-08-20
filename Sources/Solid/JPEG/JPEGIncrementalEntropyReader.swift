struct JPEGIncrementalEntropyReader {

  struct Checkpoint {
    let offset: Int
    let currentByte: UInt8
    let remainingBits: Int
  }

  private var bytes: ContiguousArray<UInt8> = []
  private var offset = 0
  private var currentByte: UInt8 = 0
  private var remainingBits = 0

  var bufferedByteCount: Int { bytes.count - offset }

  mutating func append<S: Sequence>(contentsOf source: S) where S.Element == UInt8 {
    bytes.append(contentsOf: source)
  }

  func checkpoint() -> Checkpoint {
    Checkpoint(offset: offset, currentByte: currentByte, remainingBits: remainingBits)
  }

  mutating func restore(_ checkpoint: Checkpoint) {
    offset = checkpoint.offset
    currentByte = checkpoint.currentByte
    remainingBits = checkpoint.remainingBits
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
    guard offset < bytes.count, bytes[offset] == 0xFF else { throw JPEGError.truncatedData }
    while offset < bytes.count, bytes[offset] == 0xFF { offset += 1 }
    guard offset < bytes.count else { throw JPEGError.truncatedData }
    guard bytes[offset] == 0xD0 + expected else { throw JPEGError.invalidData }
    offset += 1
  }

  mutating func compact() {
    guard offset > 0 else { return }
    bytes.removeFirst(offset)
    offset = 0
  }

  mutating func finishScan() -> [UInt8] {
    remainingBits = 0
    let result = Array(bytes[offset...])
    bytes.removeAll(keepingCapacity: true)
    offset = 0
    return result
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

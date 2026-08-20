struct CheckedByteReader {

  private let bytes: [UInt8]
  private(set) var offset: Int

  init(bytes: [UInt8], offset: Int = 0) throws {
    guard offset >= 0, offset <= bytes.count else { throw JPEGError.invalidData }
    self.bytes = bytes
    self.offset = offset
  }

  var remainingCount: Int { bytes.count - offset }

  mutating func readByte() throws -> UInt8 {
    guard offset < bytes.count else { throw JPEGError.truncatedData }
    defer { offset += 1 }
    return bytes[offset]
  }

  mutating func readUInt16() throws -> UInt16 {
    let high = UInt16(try readByte())
    let low = UInt16(try readByte())
    return high << 8 | low
  }

  mutating func readBytes(count: Int) throws -> [UInt8] {
    guard count >= 0, count <= remainingCount else { throw JPEGError.truncatedData }
    defer { offset += count }
    return Array(bytes[offset..<(offset + count)])
  }

}

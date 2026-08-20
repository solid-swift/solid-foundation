struct CheckedByteWriter {

  private(set) var bytes: [UInt8] = []
  private let maximumBytes: Int

  init(maximumBytes: Int) throws {
    guard maximumBytes >= 0 else { throw JPEGError.invalidConfiguration("maximumBytes") }
    self.maximumBytes = maximumBytes
  }

  mutating func append(_ byte: UInt8) throws {
    try reserve(additionalCount: 1)
    bytes.append(byte)
  }

  mutating func append(contentsOf newBytes: [UInt8]) throws {
    try reserve(additionalCount: newBytes.count)
    bytes.append(contentsOf: newBytes)
  }

  mutating func appendUInt16(_ value: UInt16) throws {
    try reserve(additionalCount: 2)
    bytes.append(UInt8(value >> 8))
    bytes.append(UInt8(value & 0xFF))
  }

  private func reserve(additionalCount: Int) throws {
    guard additionalCount >= 0, additionalCount <= maximumBytes - bytes.count else {
      throw JPEGError.limitExceeded
    }
  }

}

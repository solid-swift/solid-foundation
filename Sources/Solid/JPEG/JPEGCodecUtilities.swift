enum JPEGCodecUtilities {

  static func ceilDivide(_ value: Int, by divisor: Int) -> Int {
    (value + divisor - 1) / divisor
  }

  static func magnitudeCategory(_ value: Int) -> Int {
    guard value != 0 else { return 0 }
    return Int.bitWidth - abs(value).leadingZeroBitCount
  }

  static func encodedMagnitude(_ value: Int, category: Int) -> UInt32 {
    if value >= 0 { return UInt32(value) }
    return UInt32(value + (1 << category) - 1)
  }

  static func decodedMagnitude(_ value: Int, category: Int) -> Int {
    guard category > 0 else { return 0 }
    let threshold = 1 << (category - 1)
    return value < threshold ? value - (1 << category) + 1 : value
  }

  static func naturalQuantization(_ table: JPEGQuantizationTable) -> [Int] {
    var values = [Int](repeating: 0, count: 64)
    for zigzagIndex in 0..<64 {
      values[JPEGConstants.zigzag[zigzagIndex]] = Int(table.values[zigzagIndex])
    }
    return values
  }

}

#if canImport(Darwin)
  import Darwin
#else
  import Glibc
#endif

enum JPEGDCT {

  private static let cosine: [[Double]] = (0..<8).map { frequency in
    (0..<8).map { sample in
      cos((Double(2 * sample + 1) * Double(frequency) * Double.pi) / 16)
    }
  }

  static func forward(samples: [UInt8], coefficients: inout [Int]) {
    precondition(samples.count == 64 && coefficients.count == 64)
    for verticalFrequency in 0..<8 {
      let verticalScale = verticalFrequency == 0 ? 1 / sqrt(2.0) : 1
      for horizontalFrequency in 0..<8 {
        let horizontalScale = horizontalFrequency == 0 ? 1 / sqrt(2.0) : 1
        var sum = 0.0
        for y in 0..<8 {
          for x in 0..<8 {
            sum += (Double(samples[y * 8 + x]) - 128)
              * cosine[horizontalFrequency][x]
              * cosine[verticalFrequency][y]
          }
        }
        coefficients[verticalFrequency * 8 + horizontalFrequency] = Int(
          (0.25 * horizontalScale * verticalScale * sum).rounded()
        )
      }
    }
  }

  static func inverse(coefficients: [Int], samples: inout [UInt8]) {
    precondition(coefficients.count == 64 && samples.count == 64)
    for y in 0..<8 {
      for x in 0..<8 {
        var sum = 0.0
        for verticalFrequency in 0..<8 {
          let verticalScale = verticalFrequency == 0 ? 1 / sqrt(2.0) : 1
          for horizontalFrequency in 0..<8 {
            let horizontalScale = horizontalFrequency == 0 ? 1 / sqrt(2.0) : 1
            sum += horizontalScale * verticalScale
              * Double(coefficients[verticalFrequency * 8 + horizontalFrequency])
              * cosine[horizontalFrequency][x]
              * cosine[verticalFrequency][y]
          }
        }
        samples[y * 8 + x] = clampByte(Int((0.25 * sum + 128).rounded()))
      }
    }
  }

  static func clampByte(_ value: Int) -> UInt8 {
    UInt8(clamping: min(255, max(0, value)))
  }

}

import Foundation
import SolidJPEGBenchmarkSupport

let iterations = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 50
let size = CommandLine.arguments.dropFirst(2).first.flatMap(Int.init) ?? 512
let startupDelay = CommandLine.arguments.dropFirst(3).first.flatMap(Double.init) ?? 0
guard iterations > 0, size > 0 else {
  fatalError("The iteration count and image size must be positive")
}
if startupDelay > 0 {
  Thread.sleep(forTimeInterval: startupDelay)
}

let workload = try JPEGBenchmarkFixtures.all(width: size, height: size).last!
var checksum: UInt64 = 0
for _ in 0..<iterations {
  for byte in try JPEGBenchmarkFixtures.encode(workload, backend: .native) {
    checksum = checksum &* 16_777_619 ^ UInt64(byte)
  }
  for byte in try JPEGBenchmarkFixtures.decode(workload, backend: .native) {
    checksum = checksum &* 16_777_619 ^ UInt64(byte)
  }
}
print(checksum)

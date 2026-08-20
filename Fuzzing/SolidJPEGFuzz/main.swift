import SolidFuzzSupport
import SolidJPEG

let configuration = try DeterministicFuzzConfiguration.commandLine()
let validJPEG = try makeValidJPEG()
let runner = DeterministicFuzzRunner(
  configuration: configuration,
  builtInCorpus: [
    validJPEG,
    [0xFF, 0xD8, 0xFF, 0xD9],
    [0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x0B, 8, 0, 1, 0, 1, 1, 1, 0x11, 0, 0xFF, 0xD9],
  ]
)
try runner.run { input, iteration in
  var decoder = JPEGDecoder()
  var offset = 0
  var chunk = max(1, iteration % 31)
  while offset < input.count {
    let count = min(chunk, input.count - offset)
    let result = try input[offset..<(offset + count)].withUnsafeBufferPointer {
      try decoder.process(Span(_unsafeElements: $0))
    }
    offset += result.consumedBytes
    if result.progress == .finished { break }
    chunk = chunk % 31 + 1
  }
  if offset == input.count { _ = try decoder.finish() }

  guard input.count >= 4 else { return }
  let width = Int(input[0] & 31) + 1
  let height = Int(input[1] & 31) + 1
  let components = Int(input[2] % 4) + 1
  let required = width * height * components
  guard input.count - 3 >= required else { return }
  let frame = (0..<components).map { index in
    try! JPEGComponent(identifier: UInt8(index + 1))
  }
  var encoder = JPEGEncoder(
    options: try JPEGEncodingOptions(
      width: width,
      height: height,
      components: frame,
      restartInterval: Int(input[3])
    )
  )
  _ = try input[3..<(3 + required)].withUnsafeBufferPointer {
    try encoder.process(Span(_unsafeElements: $0))
  }
  _ = try encoder.finish()
}

private func makeValidJPEG() throws -> [UInt8] {
  let options = try JPEGEncodingOptions(
    width: 16,
    height: 16,
    components: [JPEGComponent(identifier: 1)]
  )
  var encoder = JPEGEncoder(options: options)
  let samples = [UInt8](repeating: 127, count: 256)
  let result = try samples.withUnsafeBufferPointer {
    try encoder.process(Span(_unsafeElements: $0))
  }
  return result.bytes + (try encoder.finish())
}

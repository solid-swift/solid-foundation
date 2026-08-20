import Foundation
import SolidFuzzSupport
import SolidIO

let configuration = try DeterministicFuzzConfiguration.commandLine()
let runner = DeterministicFuzzRunner(
  configuration: configuration,
  builtInCorpus: [
    [0x00],
    [0x00, 0x10, 0x01],
    [0xFF, 0xFF, 0x00, 0x00],
    [0x00, 0x10, 0x01, 0x00, 0x10, 0x01],
  ]
)
try runner.run { input, iteration in
  let kValues = [-1, 0, 1, 2]
  let options = try CCITTFaxOptions(
    k: kValues[iteration % kValues.count],
    endOfLine: iteration & 1 != 0,
    encodedByteAlign: iteration & 2 != 0,
    columns: max(1, min(1_728, (input.first.map(Int.init) ?? 0) * 8 + 1)),
    rows: max(1, min(256, input.dropFirst().first.map(Int.init) ?? 1)),
    endOfBlock: iteration & 4 == 0,
    blackIs1: iteration & 8 != 0,
    damagedRowsBeforeError: iteration % 4
  )
  let decoder = CCITTFaxDecoder(options: options)
  var offset = 0
  while offset < input.count {
    let count = min(input.count - offset, iteration % 17 + 1)
    let result = try decoder.process(input: Data(input[offset..<(offset + count)]))
    offset += result.consumedInput
    if result.progress == .finished { break }
  }
  _ = try decoder.finish()
}

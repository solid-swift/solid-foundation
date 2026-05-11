//
//  main.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/24/25.
//

import Foundation
import SolidData
import SolidIO
import SolidNumeric
import SolidJSON
import SolidYAML
import ArgumentParser

@main
struct ExcerciseNumerics: AsyncParsableCommand {

  static let configuration = CommandConfiguration(
    abstract: "Excerise Numerics",
    subcommands: [
      ExceriseBigDecimal.self,
      ExceriseBigUInt.self,
      ExceriseBigInt.self,
      ExceriseYAMLDecode.self,
      ExceriseJSONDecode.self,
      ExceriseYAMLFile.self,
    ]
  )
}

struct ExceriseBigDecimal: ParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "excercise-bigdecimal",
    abstract: "Excerise BigDecimal",
    discussion: """
    Excerise BigDecimal

    This command is used to exercise the BigDecimal type. It performs a multiplication,
    division, and remainder operation on `iterations` of random BigDecimal values.
    """,
    aliases: ["ebd"]
  )

  @Argument(help: "The number of iterations to run")
  var iterations: Int = 10_000_000

  @Flag(name: .shortAndLong, help: "Print the duration of the operation")
  var printDuration: Bool = false

  func run() throws {

    let clock = ContinuousClock()
    let start = clock.now

    for _ in 0..<iterations {
      let s = BigDecimal(UInt.random(in: .min ... .max))
      let t = BigDecimal(UInt.random(in: .min ... .max))
      let p = s * t
      let q = p / s
      let r = p.remainder(dividingBy: s)
      blackHole(q)
      blackHole(r)
    }

    let end = clock.now
    let duration = end - start

    if printDuration {
      print("Duration: \(duration)")
    }
  }
}

struct ExceriseBigUInt: ParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "excercise-biguint",
    abstract: "Excerise BigUInt",
    discussion: """
    Excerise BigUInt

    This command is used to exercise the BigUInt type. It performs a multiplication,
    division/remainder operation on `iterations` of random BigUInt values.
    """,
    aliases: ["ebu"]
  )

  @Argument(help: "The number of iterations to run")
  var iterations: Int = 10_000_000

  @Flag(help: "Print the duration of the operation")
  var printDuration: Bool = false

  func run() throws {

    let clock = ContinuousClock()
    let start = clock.now

    for _ in 0..<iterations {
      let s = BigUInt(UInt.random(in: .min ... .max))
      let t = BigUInt(UInt.random(in: .min ... .max))
      let p = s * t
      let (q, r) = p.quotientAndRemainder(dividingBy: s)
      blackHole(q)
      blackHole(r)
    }

    let end = clock.now
    let duration = end - start

    if printDuration {
      print("Duration: \(duration)")
    }
  }
}

struct ExceriseBigInt: ParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "excercise-bigint",
    abstract: "Excerise BigInt",
    discussion: """
    Excerise BigInt

    This command is used to exercise the BigInt type. It performs a multiplication,
    division/remainder operation on `iterations` of random BigInt values.
    """,
    aliases: ["ebi"]
  )

  @Argument(help: "The number of iterations to run")
  var iterations: Int = 10_000_000

  @Flag(help: "Print the duration of the operation")
  var printDuration: Bool = false

  func run() throws {

    let clock = ContinuousClock()
    let start = clock.now

    for _ in 0..<iterations {
      let s = BigInt(Int.random(in: .min ... .max))
      let t = BigInt(Int.random(in: .min ... .max))
      let p = s * t
      let (q, r) = p.quotientAndRemainder(dividingBy: s)
      blackHole(q)
      blackHole(r)
    }

    let end = clock.now
    let duration = end - start

    if printDuration {
      print("Duration: \(duration)")
    }
  }
}

struct ExceriseYAMLDecode: ParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "excercise-yaml-decode",
    abstract: "Excerise YAML Decode",
    discussion: """
    Excerise YAML decoding of a large array.

    This command is used to exercise the YAML decode path. It decodes a large YAML
    array (10k integers) for the specified number of iterations.
    """,
    aliases: ["eyd"]
  )

  @Argument(help: "The number of iterations to run")
  var iterations: Int = 20

  @Flag(name: .shortAndLong, help: "Print the duration of the operation")
  var printDuration: Bool = false

  func run() throws {

    let largeArray: Value = .array((0..<10_000).map { .number($0) })
    let largeArrayYaml = try YAMLValueWriter.write(largeArray)

    // Warm up
    var warmupReader = try YAMLValueReader(data: largeArrayYaml)
    blackHole(try warmupReader.read())

    let clock = ContinuousClock()
    let start = clock.now

    for _ in 0..<iterations {
      var reader = try YAMLValueReader(data: largeArrayYaml)
      blackHole(try reader.read())
    }

    let end = clock.now
    let duration = end - start

    if printDuration {
      let perIteration = duration / iterations
      print("Duration: \(duration) (\(perIteration) per iteration)")
    }
  }
}

struct ExceriseJSONDecode: ParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "excercise-json-decode",
    abstract: "Excerise JSON Decode",
    discussion: """
    Excerise JSON decoding of a large array.

    This command is used to exercise the JSON decode path. It decodes a large JSON
    array (10k integers) for the specified number of iterations.
    """,
    aliases: ["ejd"]
  )

  @Argument(help: "The number of iterations to run")
  var iterations: Int = 20

  @Flag(name: .shortAndLong, help: "Print the duration of the operation")
  var printDuration: Bool = false

  func run() throws {

    let largeArray: Value = .array((0..<10_000).map { .number($0) })
    let largeArrayJson = try JSONValueWriter.write(largeArray)

    // Warm up
    var warmupReader = JSONValueReader(data: largeArrayJson)
    blackHole(try warmupReader.read())

    let clock = ContinuousClock()
    let start = clock.now

    for _ in 0..<iterations {
      var reader = JSONValueReader(data: largeArrayJson)
      blackHole(try reader.read())
    }

    let end = clock.now
    let duration = end - start

    if printDuration {
      let perIteration = duration / iterations
      print("Duration: \(duration) (\(perIteration) per iteration)")
    }
  }
}

struct ExceriseYAMLFile: AsyncParsableCommand {

  enum Mode: String, ExpressibleByArgument {
    case eventNext = "event-next"
    case eventBatch = "event-batch"
    case documentValues = "document-values"
  }

  static let configuration = CommandConfiguration(
    commandName: "excercise-yaml-file",
    abstract: "Excerise YAML file streaming",
    discussion: """
    Excerise YAML decoding of a file-backed document stream.

    Use event-next to measure one async driver call per returned event,
    event-batch to measure batched event consumption, and document-values to
    measure the public YAMLDocumentStreamReader value path.
    """,
    aliases: ["eyf"]
  )

  @Argument(help: "Path to the YAML file to read")
  var path: String

  @Option(name: .shortAndLong, help: "Reader mode: event-next, event-batch, or document-values")
  var mode: Mode = .eventBatch

  @Option(help: "Input source buffer size")
  var bufferSize: Int = BufferedSource.segmentSize

  @Option(help: "Event output batch capacity for event-next and event-batch")
  var outputCapacity: Int = 64

  @Flag(name: .shortAndLong, help: "Print the duration of the operation")
  var printDuration: Bool = false

  func run() async throws {
    let clock = ContinuousClock()
    let start = clock.now
    let result =
      switch mode {
      case .eventNext:
        try await readEventsWithNext()
      case .eventBatch:
        try await readEventsWithBatch()
      case .documentValues:
        try await readDocumentValues()
      }
    let duration = clock.now - start

    print("mode=\(mode.rawValue)")
    print("bytes=\(result.bytes)")
    print("documents=\(result.documents)")
    print("events=\(result.events)")
    if printDuration {
      print("duration=\(duration)")
    }
  }

  private func readEventsWithNext() async throws -> YAMLFileResult {
    try await withFileSource { source in
      let driver = FormatDocumentStreamReaderDriver(
        reader: YAMLDocumentEventReader(),
        source: source,
        bufferSize: bufferSize,
        outputCapacity: outputCapacity
      )

      var result = YAMLFileResult()
      while let event = try await driver.next() {
        result.append(event)
      }
      result.bytes = source.bytesRead
      return result
    }
  }

  private func readEventsWithBatch() async throws -> YAMLFileResult {
    try await withFileSource { source in
      let driver = FormatDocumentStreamReaderDriver(
        reader: YAMLDocumentEventReader(),
        source: source,
        bufferSize: bufferSize,
        outputCapacity: outputCapacity
      )

      var result = YAMLFileResult()
      while true {
        let status = try await driver.readBatch { events in
          for event in events {
            result.append(event)
          }
        }
        if status == .endOfStream {
          result.bytes = source.bytesRead
          return result
        }
      }
    }
  }

  private func readDocumentValues() async throws -> YAMLFileResult {
    try await withFileSource { source in
      let reader = YAMLDocumentStreamReader(source: source, bufferSize: bufferSize)

      var result = YAMLFileResult()
      while let document = try await reader.next() {
        result.documents += 1
        blackHole(document)
      }
      result.bytes = source.bytesRead
      return result
    }
  }

  private func withFileSource<T>(
    _ body: (FileSource) async throws -> T
  ) async throws -> T {
    let source = try FileSource(path: path)
    do {
      let result = try await body(source)
      try await source.close()
      return result
    } catch {
      try? await source.close()
      throw error
    }
  }
}

private struct YAMLFileResult {
  var bytes = 0
  var documents = 0
  var events = 0

  mutating func append(_ event: ParseDocumentEvent) {
    events += 1
    if case .startDocument = event {
      documents += 1
    }
  }
}

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
import Synchronization

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
    case valueWrite = "value-write"
    case documentWrite = "document-write"
  }

  enum WriteSink: String, ExpressibleByArgument {
    case discard
    case data
  }

  static let configuration = CommandConfiguration(
    commandName: "excercise-yaml-file",
    abstract: "Excerise YAML file streaming",
    discussion: """
    Excerise YAML decoding and encoding of a file-backed document stream.

    Use event-next to measure one async driver call per returned event,
    event-batch to measure batched event consumption, and document-values to
    measure the public YAMLDocumentStreamReader value path. Use value-write to
    parse the file before timing and measure YAMLValueWriter output. Use
    document-write to parse the file before timing and measure
    YAMLDocumentStreamWriter output.
    """,
    aliases: ["eyf"]
  )

  @Argument(help: "Path to the YAML file to read")
  var path: String

  @Option(
    name: .shortAndLong,
    help: "Mode: event-next, event-batch, document-values, value-write, or document-write"
  )
  var mode: Mode = .eventBatch

  @Option(help: "Input source buffer size")
  var bufferSize: Int = BufferedSource.segmentSize

  @Option(help: "Event output batch capacity for event-next and event-batch")
  var outputCapacity: Int = 64

  @Option(help: "Number of write iterations for value-write and document-write")
  var iterations: Int = 1

  @Option(help: "Sink for document-write mode: discard or data")
  var writeSink: WriteSink = .discard

  @Option(help: "Write one generated output stream to this path after timing")
  var outputPath: String?

  @Flag(help: "Validate write output after timing")
  var validateOutput: Bool = false

  @Flag(name: .shortAndLong, help: "Print the duration of the operation")
  var printDuration: Bool = false

  func run() async throws {
    guard iterations > 0 else {
      throw YAMLFileBenchmarkError.invalidIterations(iterations)
    }

    let clock = ContinuousClock()
    let result: YAMLFileResult
    let duration: Duration

    switch mode {
    case .eventNext:
      let start = clock.now
      result = try await readEventsWithNext()
      duration = clock.now - start
    case .eventBatch:
      let start = clock.now
      result = try await readEventsWithBatch()
      duration = clock.now - start
    case .documentValues:
      let start = clock.now
      result = try await readDocumentValues()
      duration = clock.now - start
    case .valueWrite:
      let prepared = try await readPreparedDocuments()
      let start = clock.now
      result = try writeValues(prepared.documents, inputBytes: prepared.bytes)
      duration = clock.now - start
      if let outputPath {
        try writeValueOutput(prepared.documents, to: outputPath)
      }
      if validateOutput {
        try validateValueWrite(prepared.documents)
      }
    case .documentWrite:
      let prepared = try await readPreparedDocuments()
      let start = clock.now
      result = try await writeDocuments(prepared.documents, inputBytes: prepared.bytes)
      duration = clock.now - start
      if let outputPath {
        try await writeDocumentOutput(prepared.documents, to: outputPath)
      }
      if validateOutput {
        try await validateDocumentWrite(prepared.documents)
      }
    }

    print("mode=\(mode.rawValue)")
    print("bytes=\(result.bytes)")
    if result.outputBytes > 0 {
      print("output-bytes=\(result.outputBytes)")
    }
    print("documents=\(result.documents)")
    print("events=\(result.events)")
    if result.iterations > 1 {
      print("iterations=\(result.iterations)")
    }
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

  private func readPreparedDocuments() async throws -> (documents: [YAMLValueDocument], bytes: Int) {
    try await withFileSource { source in
      let reader = YAMLDocumentStreamReader(source: source, bufferSize: bufferSize)
      var documents: [YAMLValueDocument] = []
      while let document = try await reader.next() {
        documents.append(document)
      }
      return (documents, source.bytesRead)
    }
  }

  private func writeValues(_ documents: [YAMLValueDocument], inputBytes: Int) throws -> YAMLFileResult {
    let writer = YAMLValueWriter(options: .default)
    var result = YAMLFileResult(bytes: inputBytes, iterations: iterations)

    for _ in 0..<iterations {
      for document in documents {
        let data = try writer.write(document.value)
        result.outputBytes += data.count
        result.documents += 1
        blackHole(data.count)
      }
    }

    return result
  }

  private func writeDocuments(_ documents: [YAMLValueDocument], inputBytes: Int) async throws -> YAMLFileResult {
    var result = YAMLFileResult(bytes: inputBytes, iterations: iterations)

    for _ in 0..<iterations {
      switch writeSink {
      case .discard:
        let sink = CountingSink()
        let writer = YAMLDocumentStreamWriter(sink: sink, options: .default)
        for document in documents {
          try await writer.write(document)
          result.documents += 1
        }
        try await writer.close()
        result.outputBytes += sink.bytesWritten
      case .data:
        let sink = DataSink()
        let writer = YAMLDocumentStreamWriter(sink: sink, options: .default)
        for document in documents {
          try await writer.write(document)
          result.documents += 1
        }
        try await writer.close()
        result.outputBytes += sink.bytesWritten
        blackHole(sink.data.count)
      }
    }

    return result
  }

  private func validateValueWrite(_ documents: [YAMLValueDocument]) throws {
    for document in documents {
      let data = try YAMLValueWriter.write(document.value)
      var reader = try YAMLValueReader(data: data)
      let value = try reader.read()
      guard value == document.value else {
        throw YAMLFileBenchmarkError.validationMismatch
      }
    }
  }

  private func validateDocumentWrite(_ documents: [YAMLValueDocument]) async throws {
    let sink = DataSink()
    let writer = YAMLDocumentStreamWriter(sink: sink, options: .default)
    for document in documents {
      try await writer.write(document)
    }
    try await writer.close()

    let reader = try YAMLDocumentReader(data: sink.data)
    let writtenDocuments = try reader.readAll()
    guard writtenDocuments == documents else {
      throw YAMLFileBenchmarkError.validationMismatch
    }
  }

  private func writeValueOutput(_ documents: [YAMLValueDocument], to path: String) throws {
    var output = Data()
    let writer = YAMLValueWriter(options: .default)
    for (index, document) in documents.enumerated() {
      if index > 0 {
        output.append(Data("---\n".utf8))
      }
      output.append(try writer.write(document.value))
    }
    try output.write(to: URL(fileURLWithPath: path))
  }

  private func writeDocumentOutput(_ documents: [YAMLValueDocument], to path: String) async throws {
    let sink = DataSink()
    let writer = YAMLDocumentStreamWriter(sink: sink, options: .default)
    for document in documents {
      try await writer.write(document)
    }
    try await writer.close()
    try sink.data.write(to: URL(fileURLWithPath: path))
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
  var outputBytes = 0
  var documents = 0
  var events = 0
  var iterations = 1

  mutating func append(_ event: ParseDocumentEvent) {
    events += 1
    if case .startDocument = event {
      documents += 1
    }
  }
}

private final class CountingSink: Sink, @unchecked Sendable {

  private struct State {
    var bytesWritten = 0
    var closed = false
  }

  private let state = Mutex(State())

  var bytesWritten: Int {
    state.withLock { $0.bytesWritten }
  }

  func write(data: Data) throws {
    try state.withLock { state in
      guard !state.closed else {
        throw IOError.streamClosed
      }
      state.bytesWritten += data.count
    }
  }

  func close() {
    state.withLock { $0.closed = true }
  }
}

private enum YAMLFileBenchmarkError: Error, CustomStringConvertible {
  case invalidIterations(Int)
  case validationMismatch

  var description: String {
    switch self {
    case .invalidIterations(let iterations):
      return "Iterations must be greater than zero, got \(iterations)"
    case .validationMismatch:
      return "Written YAML did not read back to the prepared document values"
    }
  }
}

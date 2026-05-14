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
import SolidCBOR
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
      ExceriseYAMLToJSONFile.self,
      ExceriseJSONFile.self,
      ExceriseJSONToCBORFile.self,
      ExceriseCBORFile.self,
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

struct ExceriseYAMLToJSONFile: AsyncParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "convert-yaml-json-file",
    abstract: "Convert a YAML value document stream to JSON",
    discussion: """
    Reads a YAML file through YAMLDocumentStreamReader and writes JSON with JSONValueWriter.
    Single-document YAML is written as that document's value. Multi-document YAML is written
    as a JSON array containing each document value.
    """,
    aliases: ["y2j"]
  )

  @Argument(help: "Path to the YAML file to read")
  var inputPath: String

  @Argument(help: "Path to the JSON file to write")
  var outputPath: String

  @Option(help: "Input source buffer size")
  var bufferSize: Int = BufferedSource.segmentSize

  @Flag(name: .shortAndLong, help: "Print the duration of the conversion")
  var printDuration: Bool = false

  func run() async throws {
    let clock = ContinuousClock()
    let start = clock.now

    let documents = try await readDocuments()
    let value: Value
    if documents.count == 1, let document = documents.first {
      value = document.value
    } else {
      value = .array(documents.map(\.value))
    }

    let data = try JSONValueWriter.write(value)
    try data.write(to: URL(fileURLWithPath: outputPath))

    let duration = clock.now - start
    print("input-bytes=\((try FileManager.default.attributesOfItem(atPath: inputPath)[.size] as? NSNumber)?.intValue ?? 0)")
    print("output-bytes=\(data.count)")
    print("documents=\(documents.count)")
    if printDuration {
      print("duration=\(duration)")
    }
  }

  private func readDocuments() async throws -> [YAMLValueDocument] {
    let source = try FileSource(path: inputPath)
    do {
      let reader = YAMLDocumentStreamReader(source: source, bufferSize: bufferSize)
      var documents: [YAMLValueDocument] = []
      while let document = try await reader.next() {
        documents.append(document)
      }
      try await source.close()
      return documents
    } catch {
      try? await source.close()
      throw error
    }
  }
}

struct ExceriseJSONFile: AsyncParsableCommand {

  enum Mode: String, ExpressibleByArgument {
    case eventNext = "event-next"
    case eventBatch = "event-batch"
    case valueRead = "value-read"
    case valueWrite = "value-write"
    case streamWrite = "stream-write"
    case streamValueWrite = "stream-value-write"
  }

  enum WriteSink: String, ExpressibleByArgument {
    case discard
    case data
  }

  static let configuration = CommandConfiguration(
    commandName: "excercise-json-file",
    abstract: "Excerise JSON file streaming",
    discussion: """
    Excerise JSON decoding and encoding of a large file.

    Use event-next to measure one async driver call per returned event,
    event-batch to measure batched event consumption, and value-read to measure
    JSONValueReader. Use value-write to parse the file before timing and measure
    JSONValueWriter output. Use stream-write to parse the file before timing and
    measure JSONStreamWriter output one event at a time. Use stream-value-write
    to measure the bulk value stream path.
    """,
    aliases: ["ejf"]
  )

  @Argument(help: "Path to the JSON file to read")
  var path: String

  @Option(
    name: .shortAndLong,
    help: "Mode: event-next, event-batch, value-read, value-write, stream-write, or stream-value-write"
  )
  var mode: Mode = .valueRead

  @Option(help: "Input source buffer size")
  var bufferSize: Int = BufferedSource.segmentSize

  @Option(help: "Event output batch capacity for event-next and event-batch")
  var outputCapacity: Int = 64

  @Option(help: "Number of write or value-read iterations")
  var iterations: Int = 1

  @Option(help: "Sink for stream-write mode: discard or data")
  var writeSink: WriteSink = .discard

  @Option(help: "Write one generated output stream to this path after timing")
  var outputPath: String?

  @Flag(help: "Validate write output after timing")
  var validateOutput: Bool = false

  @Flag(name: .shortAndLong, help: "Print the duration of the operation")
  var printDuration: Bool = false

  func run() async throws {
    guard iterations > 0 else {
      throw JSONFileBenchmarkError.invalidIterations(iterations)
    }

    let clock = ContinuousClock()
    let result: JSONFileResult
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
    case .valueRead:
      let data = try Data(contentsOf: URL(fileURLWithPath: path))
      let start = clock.now
      result = try readValue(data)
      duration = clock.now - start
    case .valueWrite:
      let prepared = try readPreparedValue()
      let start = clock.now
      result = try writeValue(prepared.value, inputBytes: prepared.bytes)
      duration = clock.now - start
      if let outputPath {
        try writeValueOutput(prepared.value, to: outputPath)
      }
      if validateOutput {
        try validateValueWrite(prepared.value)
      }
    case .streamWrite:
      let prepared = try readPreparedValue()
      let start = clock.now
      result = try await writeStream(prepared.value, inputBytes: prepared.bytes)
      duration = clock.now - start
      if let outputPath {
        try await writeStreamOutput(prepared.value, to: outputPath)
      }
      if validateOutput {
        try await validateStreamWrite(prepared.value)
      }
    case .streamValueWrite:
      let prepared = try readPreparedValue()
      let start = clock.now
      result = try await writeStreamValue(prepared.value, inputBytes: prepared.bytes)
      duration = clock.now - start
      if let outputPath {
        try await writeStreamValueOutput(prepared.value, to: outputPath)
      }
      if validateOutput {
        try await validateStreamValueWrite(prepared.value)
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

  private func readEventsWithNext() async throws -> JSONFileResult {
    try await withFileSource { source in
      let driver = FormatDocumentStreamReaderDriver(
        reader: JSONDocumentEventReader(),
        source: source,
        bufferSize: bufferSize,
        outputCapacity: outputCapacity
      )

      var result = JSONFileResult()
      while let event = try await driver.next() {
        result.append(event)
      }
      result.bytes = source.bytesRead
      return result
    }
  }

  private func readEventsWithBatch() async throws -> JSONFileResult {
    try await withFileSource { source in
      let driver = FormatDocumentStreamReaderDriver(
        reader: JSONDocumentEventReader(),
        source: source,
        bufferSize: bufferSize,
        outputCapacity: outputCapacity
      )

      var result = JSONFileResult()
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

  private func readValue(_ data: Data) throws -> JSONFileResult {
    var result = JSONFileResult(bytes: data.count, iterations: iterations)
    for _ in 0..<iterations {
      var reader = JSONValueReader(data: data)
      blackHole(try reader.read())
      result.documents += 1
    }
    return result
  }

  private func readPreparedValue() throws -> (value: Value, bytes: Int) {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    var reader = JSONValueReader(data: data)
    return (try reader.read(), data.count)
  }

  private func writeValue(_ value: Value, inputBytes: Int) throws -> JSONFileResult {
    let writer = JSONValueWriter(options: .default)
    var result = JSONFileResult(bytes: inputBytes, iterations: iterations)

    for _ in 0..<iterations {
      let data = try writer.write(value)
      result.outputBytes += data.count
      result.documents += 1
      blackHole(data.count)
    }

    return result
  }

  private func writeStream(_ value: Value, inputBytes: Int) async throws -> JSONFileResult {
    var result = JSONFileResult(bytes: inputBytes, iterations: iterations)

    for _ in 0..<iterations {
      switch writeSink {
      case .discard:
        let sink = CountingSink()
        let writer = JSONStreamWriter(sink: sink, options: .default)
        try await EmitEventEncoder().emit(value) { event in
          try await writer.write(event)
          result.events += 1
        }
        try await writer.close()
        result.outputBytes += sink.bytesWritten
      case .data:
        let sink = DataSink()
        let writer = JSONStreamWriter(sink: sink, options: .default)
        try await EmitEventEncoder().emit(value) { event in
          try await writer.write(event)
          result.events += 1
        }
        try await writer.close()
        result.outputBytes += sink.data.count
        blackHole(sink.data.count)
      }
      result.documents += 1
    }

    return result
  }

  private func writeStreamValue(_ value: Value, inputBytes: Int) async throws -> JSONFileResult {
    var result = JSONFileResult(bytes: inputBytes, iterations: iterations)

    for _ in 0..<iterations {
      switch writeSink {
      case .discard:
        let sink = CountingSink()
        let writer = JSONStreamWriter(sink: sink, options: .default)
        try await writer.writeValue(value)
        try await writer.close()
        result.outputBytes += sink.bytesWritten
      case .data:
        let sink = DataSink()
        let writer = JSONStreamWriter(sink: sink, options: .default)
        try await writer.writeValue(value)
        try await writer.close()
        result.outputBytes += sink.data.count
        blackHole(sink.data.count)
      }
      result.documents += 1
    }

    return result
  }

  private func validateValueWrite(_ value: Value) throws {
    let data = try JSONValueWriter.write(value)
    var reader = JSONValueReader(data: data)
    guard try reader.read() == value else {
      throw JSONFileBenchmarkError.validationMismatch
    }
  }

  private func validateStreamWrite(_ value: Value) async throws {
    let sink = DataSink()
    let writer = JSONStreamWriter(sink: sink, options: .default)
    try await EmitEventEncoder().emit(value) { event in
      try await writer.write(event)
    }
    try await writer.close()

    var reader = JSONValueReader(data: sink.data)
    guard try reader.read() == value else {
      throw JSONFileBenchmarkError.validationMismatch
    }
  }

  private func validateStreamValueWrite(_ value: Value) async throws {
    let sink = DataSink()
    let writer = JSONStreamWriter(sink: sink, options: .default)
    try await writer.writeValue(value)
    try await writer.close()

    var reader = JSONValueReader(data: sink.data)
    guard try reader.read() == value else {
      throw JSONFileBenchmarkError.validationMismatch
    }
  }

  private func writeValueOutput(_ value: Value, to path: String) throws {
    let data = try JSONValueWriter.write(value)
    try data.write(to: URL(fileURLWithPath: path))
  }

  private func writeStreamOutput(_ value: Value, to path: String) async throws {
    let sink = DataSink()
    let writer = JSONStreamWriter(sink: sink, options: .default)
    try await EmitEventEncoder().emit(value) { event in
      try await writer.write(event)
    }
    try await writer.close()
    try sink.data.write(to: URL(fileURLWithPath: path))
  }

  private func writeStreamValueOutput(_ value: Value, to path: String) async throws {
    let sink = DataSink()
    let writer = JSONStreamWriter(sink: sink, options: .default)
    try await writer.writeValue(value)
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

private struct JSONFileResult {
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

private enum JSONFileBenchmarkError: Error, CustomStringConvertible {
  case invalidIterations(Int)
  case validationMismatch

  var description: String {
    switch self {
    case .invalidIterations(let iterations):
      return "Iterations must be greater than zero, got \(iterations)"
    case .validationMismatch:
      return "Written JSON did not read back to the prepared value"
    }
  }
}

struct ExceriseJSONToCBORFile: ParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "convert-json-cbor-file",
    abstract: "Convert a JSON value to CBOR",
    discussion: """
    Reads a JSON file with JSONValueReader and writes the same value as CBOR.
    """,
    aliases: ["j2c"]
  )

  @Argument(help: "Path to the JSON file to read")
  var inputPath: String

  @Argument(help: "Path to the CBOR file to write")
  var outputPath: String

  @Flag(name: .shortAndLong, help: "Print the duration of the conversion")
  var printDuration: Bool = false

  func run() throws {
    let clock = ContinuousClock()
    let start = clock.now

    let input = try Data(contentsOf: URL(fileURLWithPath: inputPath))
    var reader = JSONValueReader(data: input)
    let value = try reader.read()
    let output = try CBORValueWriter.write(value)
    try output.write(to: URL(fileURLWithPath: outputPath))

    print("input-bytes=\(input.count)")
    print("output-bytes=\(output.count)")
    if printDuration {
      print("duration=\(clock.now - start)")
    }
  }
}

struct ExceriseCBORFile: AsyncParsableCommand {

  enum Mode: String, ExpressibleByArgument {
    case eventNext = "event-next"
    case eventBatch = "event-batch"
    case documentValues = "document-values"
    case valueRead = "value-read"
    case valueWrite = "value-write"
    case streamWrite = "stream-write"
    case streamValueWrite = "stream-value-write"
  }

  enum WriteSink: String, ExpressibleByArgument {
    case discard
    case data
  }

  static let configuration = CommandConfiguration(
    commandName: "excercise-cbor-file",
    abstract: "Excerise CBOR file streaming",
    discussion: """
    Excerise CBOR decoding and encoding of a large file.

    Use event-next to measure one async driver call per returned event,
    event-batch to measure batched event consumption, document-values to
    measure CBORDocumentStreamReader, and value-read to measure CBORValueReader.
    Use value-write to parse the file before timing and measure CBORValueWriter
    output. Use stream-write to parse the file before timing and measure
    CBORStreamWriter output one event at a time. Use stream-value-write to
    measure the bulk value stream path.
    """,
    aliases: ["ecf"]
  )

  @Argument(help: "Path to the CBOR file to read")
  var path: String

  @Option(
    name: .shortAndLong,
    help: "Mode: event-next, event-batch, document-values, value-read, value-write, stream-write, or stream-value-write"
  )
  var mode: Mode = .valueRead

  @Option(help: "Input source buffer size")
  var bufferSize: Int = BufferedSource.segmentSize

  @Option(help: "Event output batch capacity for event-next and event-batch")
  var outputCapacity: Int = 64

  @Option(help: "Number of value-read, document-values, or write iterations")
  var iterations: Int = 1

  @Option(help: "Sink for stream-write modes: discard or data")
  var writeSink: WriteSink = .discard

  @Flag(help: "Use deterministic CBOR map ordering for write modes")
  var deterministic: Bool = false

  @Option(help: "Write one generated output stream to this path after timing")
  var outputPath: String?

  @Flag(help: "Validate write output after timing")
  var validateOutput: Bool = false

  @Flag(name: .shortAndLong, help: "Print the duration of the operation")
  var printDuration: Bool = false

  func run() async throws {
    guard iterations > 0 else {
      throw CBORFileBenchmarkError.invalidIterations(iterations)
    }

    let clock = ContinuousClock()
    let result: CBORFileResult
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
    case .valueRead:
      let data = try Data(contentsOf: URL(fileURLWithPath: path))
      let start = clock.now
      result = try readValue(data)
      duration = clock.now - start
    case .valueWrite:
      let prepared = try readPreparedValue()
      let start = clock.now
      result = try writeValue(prepared.value, inputBytes: prepared.bytes)
      duration = clock.now - start
      if let outputPath {
        try writeValueOutput(prepared.value, to: outputPath)
      }
      if validateOutput {
        try validateValueWrite(prepared.value)
      }
    case .streamWrite:
      let prepared = try readPreparedValue()
      let start = clock.now
      result = try await writeStream(prepared.value, inputBytes: prepared.bytes)
      duration = clock.now - start
      if let outputPath {
        try await writeStreamOutput(prepared.value, to: outputPath)
      }
      if validateOutput {
        try await validateStreamWrite(prepared.value)
      }
    case .streamValueWrite:
      let prepared = try readPreparedValue()
      let start = clock.now
      result = try await writeStreamValue(prepared.value, inputBytes: prepared.bytes)
      duration = clock.now - start
      if let outputPath {
        try await writeStreamValueOutput(prepared.value, to: outputPath)
      }
      if validateOutput {
        try await validateStreamValueWrite(prepared.value)
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

  private func readEventsWithNext() async throws -> CBORFileResult {
    try await withFileSource { source in
      let driver = FormatDocumentStreamReaderDriver(
        reader: CBORDocumentEventReader(),
        source: source,
        bufferSize: bufferSize,
        outputCapacity: outputCapacity
      )

      var result = CBORFileResult()
      while let event = try await driver.next() {
        result.append(event)
      }
      result.bytes = source.bytesRead
      return result
    }
  }

  private func readEventsWithBatch() async throws -> CBORFileResult {
    try await withFileSource { source in
      let driver = FormatDocumentStreamReaderDriver(
        reader: CBORDocumentEventReader(),
        source: source,
        bufferSize: bufferSize,
        outputCapacity: outputCapacity
      )

      var result = CBORFileResult()
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

  private func readDocumentValues() async throws -> CBORFileResult {
    var result = CBORFileResult(iterations: iterations)

    for _ in 0..<iterations {
      try await withFileSource { source in
        let reader = CBORDocumentStreamReader(source: source, bufferSize: bufferSize)
        while let document = try await reader.next() {
          result.documents += 1
          blackHole(document)
        }
        result.bytes += source.bytesRead
      }
    }

    return result
  }

  private func readValue(_ data: Data) throws -> CBORFileResult {
    var result = CBORFileResult(bytes: data.count, iterations: iterations)
    for _ in 0..<iterations {
      var reader = CBORValueReader(data: data)
      blackHole(try reader.read())
      result.documents += 1
    }
    return result
  }

  private func readPreparedValue() throws -> (value: Value, bytes: Int) {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    var reader = CBORValueReader(data: data)
    return (try reader.read(), data.count)
  }

  private func writeValue(_ value: Value, inputBytes: Int) throws -> CBORFileResult {
    let writer = CBORValueWriter(options: .init(deterministic: deterministic))
    var result = CBORFileResult(bytes: inputBytes, iterations: iterations)

    for _ in 0..<iterations {
      let data = try writer.write(value)
      result.outputBytes += data.count
      result.documents += 1
      blackHole(data.count)
    }

    return result
  }

  private func writeStream(_ value: Value, inputBytes: Int) async throws -> CBORFileResult {
    var result = CBORFileResult(bytes: inputBytes, iterations: iterations)

    for _ in 0..<iterations {
      switch writeSink {
      case .discard:
        let sink = CountingSink()
        let writer = CBORStreamWriter(sink: sink, options: streamWriterOptions)
        try await EmitEventEncoder().emit(value) { event in
          try await writer.write(event)
          result.events += 1
        }
        try await writer.close()
        result.outputBytes += sink.bytesWritten
      case .data:
        let sink = DataSink()
        let writer = CBORStreamWriter(sink: sink, options: streamWriterOptions)
        try await EmitEventEncoder().emit(value) { event in
          try await writer.write(event)
          result.events += 1
        }
        try await writer.close()
        result.outputBytes += sink.bytesWritten
        blackHole(sink.data.count)
      }
      result.documents += 1
    }

    return result
  }

  private func writeStreamValue(_ value: Value, inputBytes: Int) async throws -> CBORFileResult {
    var result = CBORFileResult(bytes: inputBytes, iterations: iterations)

    for _ in 0..<iterations {
      switch writeSink {
      case .discard:
        let sink = CountingSink()
        let writer = CBORStreamWriter(sink: sink, options: streamWriterOptions)
        try await writer.writeValue(value)
        try await writer.close()
        result.outputBytes += sink.bytesWritten
      case .data:
        let sink = DataSink()
        let writer = CBORStreamWriter(sink: sink, options: streamWriterOptions)
        try await writer.writeValue(value)
        try await writer.close()
        result.outputBytes += sink.bytesWritten
        blackHole(sink.data.count)
      }
      result.documents += 1
    }

    return result
  }

  private var streamWriterOptions: CBORStreamWriter.Options {
    CBORStreamWriter.Options(deterministic: deterministic)
  }

  private func validateValueWrite(_ value: Value) throws {
    let data = try CBORValueWriter.write(value, options: .init(deterministic: deterministic))

    if deterministic {
      try validateDeterministicCBOR(data)
    } else {
      try validateCBOR(data, equals: value)
    }
  }

  private func validateStreamWrite(_ value: Value) async throws {
    let sink = DataSink()
    let writer = CBORStreamWriter(sink: sink, options: streamWriterOptions)
    try await EmitEventEncoder().emit(value) { event in
      try await writer.write(event)
    }
    try await writer.close()

    if deterministic {
      try validateDeterministicCBOR(sink.data)
    } else {
      try validateCBOR(sink.data, equals: value)
    }
  }

  private func validateStreamValueWrite(_ value: Value) async throws {
    let sink = DataSink()
    let writer = CBORStreamWriter(sink: sink, options: streamWriterOptions)
    try await writer.writeValue(value)
    try await writer.close()

    if deterministic {
      try validateDeterministicCBOR(sink.data)
    } else {
      try validateCBOR(sink.data, equals: value)
    }
  }

  private func validateCBOR(_ data: Data, equals expected: Value) throws {
    guard try readValidatedCBOR(data) == expected else {
      throw CBORFileBenchmarkError.validationMismatch
    }
  }

  private func readValidatedCBOR(_ data: Data) throws -> Value {
    var reader = CBORValueReader(data: data)
    return try reader.read()
  }

  private func validateDeterministicCBOR(_ data: Data) throws {
    let decoded = try readValidatedCBOR(data)
    let reencoded = try CBORValueWriter.write(decoded, options: .init(deterministic: true))
    guard reencoded == data else {
      throw CBORFileBenchmarkError.validationMismatch
    }
  }

  private func writeValueOutput(_ value: Value, to path: String) throws {
    let data = try CBORValueWriter.write(value, options: .init(deterministic: deterministic))
    try data.write(to: URL(fileURLWithPath: path))
  }

  private func writeStreamOutput(_ value: Value, to path: String) async throws {
    let sink = DataSink()
    let writer = CBORStreamWriter(sink: sink, options: streamWriterOptions)
    try await EmitEventEncoder().emit(value) { event in
      try await writer.write(event)
    }
    try await writer.close()
    try sink.data.write(to: URL(fileURLWithPath: path))
  }

  private func writeStreamValueOutput(_ value: Value, to path: String) async throws {
    let sink = DataSink()
    let writer = CBORStreamWriter(sink: sink, options: streamWriterOptions)
    try await writer.writeValue(value)
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

private struct CBORFileResult {
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

private enum CBORFileBenchmarkError: Error, CustomStringConvertible {
  case invalidIterations(Int)
  case validationMismatch

  var description: String {
    switch self {
    case .invalidIterations(let iterations):
      return "Iterations must be greater than zero, got \(iterations)"
    case .validationMismatch:
      return "Written CBOR did not read back to the prepared value"
    }
  }
}

//
//  FormatStreamDriverConcurrencyTests.swift
//  SolidFoundation
//
//  Created by Codex on 4/27/26.
//

import Foundation
import SolidData
import SolidIO
import Testing


@Suite("Format Stream Driver Concurrency Tests")
struct FormatStreamDriverConcurrencyTests {

  @Test("Reader driver rejects overlapping next calls", .timeLimit(.minutes(1)))
  func readerDriverRejectsOverlappingNextCalls() async throws {
    let source = BlockingSource(data: Data([0x01]))
    let driver = FormatStreamReaderDriver(
      reader: TestStreamReader(),
      source: source,
      bufferSize: 1
    )

    async let firstEvent = driver.next()
    await source.waitUntilReadStarted()

    await #expect(throws: FormatStreamDriverError.operationInProgress) {
      _ = try await driver.next()
    }

    await source.releaseRead()
    _ = try await firstEvent
    #expect(try await driver.next() == nil)
  }

  @Test("Reader driver poisons after source failure", .timeLimit(.minutes(1)))
  func readerDriverPoisonsAfterSourceFailure() async throws {
    let source = FailingSource(error: .sourceReadFailed)
    let driver = FormatStreamReaderDriver(
      reader: TestStreamReader(),
      source: source,
      bufferSize: 1
    )

    await expectReaderError(.sourceReadFailed) {
      _ = try await driver.next()
    }
    await expectReaderError(.sourceReadFailed) {
      _ = try await driver.next()
    }
  }

  @Test("Reader driver poisons after parser failure", .timeLimit(.minutes(1)))
  func readerDriverPoisonsAfterParserFailure() async throws {
    let source = OneShotSource(data: Data([0x01]))
    let driver = FormatStreamReaderDriver(
      reader: FailingStreamReader(error: .readerReadFailed),
      source: source,
      bufferSize: 1
    )

    await expectReaderError(.readerReadFailed) {
      _ = try await driver.next()
    }
    await expectReaderError(.readerReadFailed) {
      _ = try await driver.next()
    }
  }

  @Test("Document reader driver rejects overlapping next calls", .timeLimit(.minutes(1)))
  func documentReaderDriverRejectsOverlappingNextCalls() async throws {
    let source = BlockingSource(data: Data([0x01]))
    let driver = FormatDocumentStreamReaderDriver(
      reader: TestDocumentStreamReader(),
      source: source,
      bufferSize: 1
    )

    async let firstEvent = driver.next()
    await source.waitUntilReadStarted()

    await #expect(throws: FormatStreamDriverError.operationInProgress) {
      _ = try await driver.next()
    }

    await source.releaseRead()
    _ = try await firstEvent
    while try await driver.next() != nil {}
  }

  @Test("Document reader driver poisons after source failure", .timeLimit(.minutes(1)))
  func documentReaderDriverPoisonsAfterSourceFailure() async throws {
    let source = FailingSource(error: .sourceReadFailed)
    let driver = FormatDocumentStreamReaderDriver(
      reader: TestDocumentStreamReader(),
      source: source,
      bufferSize: 1
    )

    await expectReaderError(.sourceReadFailed) {
      _ = try await driver.next()
    }
    await expectReaderError(.sourceReadFailed) {
      _ = try await driver.next()
    }
  }

  @Test("Document reader driver poisons after parser failure", .timeLimit(.minutes(1)))
  func documentReaderDriverPoisonsAfterParserFailure() async throws {
    let source = OneShotSource(data: Data([0x01]))
    let driver = FormatDocumentStreamReaderDriver(
      reader: FailingDocumentStreamReader(error: .readerReadFailed),
      source: source,
      bufferSize: 1
    )

    await expectReaderError(.readerReadFailed) {
      _ = try await driver.next()
    }
    await expectReaderError(.readerReadFailed) {
      _ = try await driver.next()
    }
  }

  @Test("Writer driver rejects overlapping write and finish calls", .timeLimit(.minutes(1)))
  func writerDriverRejectsOverlappingWriteAndFinishCalls() async throws {
    let sink = BlockingSink()
    let driver = FormatStreamWriterDriver(
      encoder: TestStreamEncoder(),
      sink: sink,
      bufferSize: 8
    )

    async let firstWrite: Void = driver.write(.scalar(.number(1)))
    await sink.waitUntilWriteStarted()

    await #expect(throws: FormatStreamDriverError.operationInProgress) {
      try await driver.write(.scalar(.number(2)))
    }
    await #expect(throws: FormatStreamDriverError.operationInProgress) {
      try await driver.finish()
    }

    await sink.releaseWrites()
    try await firstWrite
    try await driver.finish()
  }

  @Test("Writer driver rejects overlapping close during write", .timeLimit(.minutes(1)))
  func writerDriverRejectsOverlappingCloseDuringWrite() async throws {
    let sink = BlockingSink()
    let driver = FormatStreamWriterDriver(
      encoder: TestStreamEncoder(),
      sink: sink,
      bufferSize: 8
    )

    async let firstWrite: Void = driver.write(.scalar(.number(1)))
    await sink.waitUntilWriteStarted()

    await #expect(throws: FormatStreamDriverError.operationInProgress) {
      try await driver.close()
    }

    await sink.releaseWrites()
    try await firstWrite
    try await driver.close()
  }

  @Test("Writer driver rejects overlapping close during finish", .timeLimit(.minutes(1)))
  func writerDriverRejectsOverlappingCloseDuringFinish() async throws {
    let sink = BlockingSink()
    let driver = FormatStreamWriterDriver(
      encoder: TestStreamEncoder(),
      sink: sink,
      bufferSize: 8
    )

    async let firstFinish: Void = driver.finish()
    await sink.waitUntilWriteStarted()

    await #expect(throws: FormatStreamDriverError.operationInProgress) {
      try await driver.close()
    }

    await sink.releaseWrites()
    try await firstFinish
  }

  @Test("Writer driver rejects writes and finish after close", .timeLimit(.minutes(1)))
  func writerDriverRejectsWritesAndFinishAfterClose() async throws {
    let sink = BlockingSink()
    let driver = FormatStreamWriterDriver(
      encoder: TestStreamEncoder(),
      sink: sink,
      bufferSize: 8
    )

    try await driver.close()

    await #expect {
      try await driver.write(.scalar(.number(1)))
    } throws: { error in
      if case IOError.streamClosed = error {
        return true
      }
      return false
    }
    await #expect {
      try await driver.finish()
    } throws: { error in
      if case IOError.streamClosed = error {
        return true
      }
      return false
    }
  }

  @Test("Writer driver poisons after write sink failure", .timeLimit(.minutes(1)))
  func writerDriverPoisonsAfterWriteSinkFailure() async throws {
    let sink = FailingSink(writeError: .writeFailed)
    let driver = FormatStreamWriterDriver(
      encoder: TestStreamEncoder(),
      sink: sink,
      bufferSize: 8
    )

    await #expect {
      try await driver.write(.scalar(.number(1)))
    } throws: { error in
      error as? TestSinkError == .writeFailed
    }

    await expectStreamClosed {
      try await driver.write(.scalar(.number(2)))
    }
    await expectStreamClosed {
      try await driver.finish()
    }
  }

  @Test("Writer driver poisons after finish sink failure", .timeLimit(.minutes(1)))
  func writerDriverPoisonsAfterFinishSinkFailure() async throws {
    let sink = FailingSink(writeError: .writeFailed)
    let driver = FormatStreamWriterDriver(
      encoder: TestStreamEncoder(),
      sink: sink,
      bufferSize: 8
    )

    await #expect {
      try await driver.finish()
    } throws: { error in
      error as? TestSinkError == .writeFailed
    }

    await expectStreamClosed {
      try await driver.write(.scalar(.number(1)))
    }
    await expectStreamClosed {
      try await driver.finish()
    }
  }

  @Test("Writer driver poisons after close sink failure", .timeLimit(.minutes(1)))
  func writerDriverPoisonsAfterCloseSinkFailure() async throws {
    let sink = FailingSink(closeError: .closeFailed)
    let driver = FormatStreamWriterDriver(
      encoder: TestStreamEncoder(),
      sink: sink,
      bufferSize: 8
    )

    await #expect {
      try await driver.close()
    } throws: { error in
      error as? TestSinkError == .closeFailed
    }

    await expectStreamClosed {
      try await driver.write(.scalar(.number(1)))
    }
    await expectStreamClosed {
      try await driver.finish()
    }
    await expectStreamClosed {
      try await driver.close()
    }
  }

  @Test("Writer driver poisons after encoder write failure", .timeLimit(.minutes(1)))
  func writerDriverPoisonsAfterEncoderWriteFailure() async throws {
    let sink = DataSink()
    let driver = FormatStreamWriterDriver(
      encoder: FailingStreamEncoder(failure: .encode),
      sink: sink,
      bufferSize: 8
    )

    await #expect {
      try await driver.write(.scalar(.number(1)))
    } throws: { error in
      error as? TestEncoderError == .encodeFailed
    }

    await expectStreamClosed {
      try await driver.write(.scalar(.number(2)))
    }
    await expectStreamClosed {
      try await driver.finish()
    }
  }

  @Test("Writer driver poisons after encoder finish failure", .timeLimit(.minutes(1)))
  func writerDriverPoisonsAfterEncoderFinishFailure() async throws {
    let sink = DataSink()
    let driver = FormatStreamWriterDriver(
      encoder: FailingStreamEncoder(failure: .finish),
      sink: sink,
      bufferSize: 8
    )

    await #expect {
      try await driver.finish()
    } throws: { error in
      error as? TestEncoderError == .finishFailed
    }

    await expectStreamClosed {
      try await driver.write(.scalar(.number(1)))
    }
    await expectStreamClosed {
      try await driver.finish()
    }
  }
}

private enum TestFormat: Format, Sendable {
  case instance

  var kind: FormatKind { .binary }

  func supports(type: ValueType) -> Bool { true }
}

private enum TestBlockingError: Error {
  case unexpectedConcurrentRead
  case unexpectedConcurrentWrite
}

private enum TestSinkError: Error, Sendable, Equatable {
  case writeFailed
  case closeFailed
}

private enum TestReaderError: Error, Sendable, Equatable {
  case sourceReadFailed
  case readerReadFailed
}

private enum TestEncoderError: Error, Sendable, Equatable {
  case encodeFailed
  case finishFailed
}

private func expectStreamClosed(
  performing operation: () async throws -> Void
) async {
  await #expect {
    try await operation()
  } throws: { error in
    if case IOError.streamClosed = error {
      return true
    }
    return false
  }
}

private func expectReaderError(
  _ expectedError: TestReaderError,
  performing operation: () async throws -> Void
) async {
  await #expect {
    try await operation()
  } throws: { error in
    error as? TestReaderError == expectedError
  }
}

private struct TestStreamReader: FormatStreamReader {

  private var emitted = false

  var format: Format { TestFormat.instance }

  mutating func read(
    input: Data,
    isFinal: Bool,
    output: inout OutputSpan<ParseEvent>
  ) throws -> FormatStreamReadStatus {
    if !emitted, !input.isEmpty {
      output.append(.scalar(.materialized(.number(1))))
      emitted = true
      return .producedOutput
    }
    return isFinal ? .endOfStream : .needMoreInput
  }
}

private struct TestDocumentStreamReader: FormatDocumentStreamReader {

  private var emitted = false

  var format: Format { TestFormat.instance }

  mutating func read(
    input: Data,
    isFinal: Bool,
    output: inout OutputSpan<ParseDocumentEvent>
  ) throws -> FormatStreamReadStatus {
    if !emitted, !input.isEmpty {
      output.append(.startDocument(.implicit))
      output.append(.event(.scalar(.materialized(.number(1)))))
      output.append(.endDocument(.implicit))
      emitted = true
      return .producedOutput
    }
    return isFinal ? .endOfStream : .needMoreInput
  }
}

private struct FailingStreamReader: FormatStreamReader {

  private let error: TestReaderError
  private var readCount = 0

  init(error: TestReaderError) {
    self.error = error
  }

  var format: Format { TestFormat.instance }

  mutating func read(
    input: Data,
    isFinal: Bool,
    output: inout OutputSpan<ParseEvent>
  ) throws -> FormatStreamReadStatus {
    readCount += 1
    throw error
  }
}

private struct FailingDocumentStreamReader: FormatDocumentStreamReader {

  private let error: TestReaderError
  private var readCount = 0

  init(error: TestReaderError) {
    self.error = error
  }

  var format: Format { TestFormat.instance }

  mutating func read(
    input: Data,
    isFinal: Bool,
    output: inout OutputSpan<ParseDocumentEvent>
  ) throws -> FormatStreamReadStatus {
    readCount += 1
    throw error
  }
}

private struct TestStreamEncoder: FormatStreamEncoder {

  var format: Format { TestFormat.instance }

  mutating func encode(
    _ event: EmitEvent,
    output: inout OutputSpan<UInt8>
  ) throws -> FormatStreamEncodeStatus {
    output.append(0x01)
    return .producedOutput
  }

  mutating func finish(
    output: inout OutputSpan<UInt8>
  ) throws -> FormatStreamEncodeStatus {
    output.append(0x02)
    return .endOfStream
  }
}

private struct FailingStreamEncoder: FormatStreamEncoder {

  enum Failure {
    case encode
    case finish
  }

  private let failure: Failure
  private var encodeCount = 0
  private var finishCount = 0

  init(failure: Failure) {
    self.failure = failure
  }

  var format: Format { TestFormat.instance }

  mutating func encode(
    _ event: EmitEvent,
    output: inout OutputSpan<UInt8>
  ) throws -> FormatStreamEncodeStatus {
    encodeCount += 1
    if failure == .encode {
      output.append(0x03)
      throw TestEncoderError.encodeFailed
    }
    output.append(0x01)
    return .producedOutput
  }

  mutating func finish(
    output: inout OutputSpan<UInt8>
  ) throws -> FormatStreamEncodeStatus {
    finishCount += 1
    if failure == .finish {
      output.append(0x04)
      throw TestEncoderError.finishFailed
    }
    output.append(0x02)
    return .endOfStream
  }
}

private actor BlockingSource: Source {

  private var storage: Data
  private var bytesReadValue = 0
  private var readStarted = false
  private var readReleased = false
  private var readStartedContinuations: [CheckedContinuation<Void, Never>] = []
  private var readReleaseContinuations: [CheckedContinuation<Void, Never>] = []

  init(data: Data) {
    self.storage = data
  }

  var bytesRead: Int {
    get async throws { bytesReadValue }
  }

  func read(max: Int) async throws -> Data? {
    guard !storage.isEmpty else { return nil }
    guard !readStarted || readReleased else {
      throw TestBlockingError.unexpectedConcurrentRead
    }

    readStarted = true
    resumeReadStartedContinuations()

    if !readReleased {
      await withCheckedContinuation { continuation in
        readReleaseContinuations.append(continuation)
      }
    }

    let count = Swift.min(max, storage.count)
    let result = Data(storage.prefix(count))
    storage.removeSubrange(0..<count)
    bytesReadValue += count
    return result
  }

  func waitUntilReadStarted() async {
    guard !readStarted else { return }

    await withCheckedContinuation { continuation in
      readStartedContinuations.append(continuation)
    }
  }

  func releaseRead() {
    readReleased = true
    let continuations = readReleaseContinuations
    readReleaseContinuations.removeAll()
    for continuation in continuations {
      continuation.resume()
    }
  }

  func close() async throws {}

  private func resumeReadStartedContinuations() {
    let continuations = readStartedContinuations
    readStartedContinuations.removeAll()
    for continuation in continuations {
      continuation.resume()
    }
  }
}

private actor FailingSource: Source {

  private let error: TestReaderError

  init(error: TestReaderError) {
    self.error = error
  }

  var bytesRead: Int {
    get async throws { 0 }
  }

  func read(max: Int) async throws -> Data? {
    throw error
  }

  func close() async throws {}
}

private actor OneShotSource: Source {

  private var storage: Data
  private var bytesReadValue = 0

  init(data: Data) {
    self.storage = data
  }

  var bytesRead: Int {
    get async throws { bytesReadValue }
  }

  func read(max: Int) async throws -> Data? {
    guard !storage.isEmpty else { return nil }
    let count = Swift.min(max, storage.count)
    let result = Data(storage.prefix(count))
    storage.removeSubrange(0..<count)
    bytesReadValue += count
    return result
  }

  func close() async throws {}
}

private actor BlockingSink: Sink {

  private var storage = Data()
  private var writeStarted = false
  private var writeReleased = false
  private var writeStartedContinuations: [CheckedContinuation<Void, Never>] = []
  private var writeReleaseContinuations: [CheckedContinuation<Void, Never>] = []

  var bytesWritten: Int {
    get async throws { storage.count }
  }

  func write(data: Data) async throws {
    guard !writeStarted || writeReleased else {
      throw TestBlockingError.unexpectedConcurrentWrite
    }

    writeStarted = true
    resumeWriteStartedContinuations()

    if !writeReleased {
      await withCheckedContinuation { continuation in
        writeReleaseContinuations.append(continuation)
      }
    }

    storage.append(data)
  }

  func waitUntilWriteStarted() async {
    guard !writeStarted else { return }

    await withCheckedContinuation { continuation in
      writeStartedContinuations.append(continuation)
    }
  }

  func releaseWrites() {
    writeReleased = true
    let continuations = writeReleaseContinuations
    writeReleaseContinuations.removeAll()
    for continuation in continuations {
      continuation.resume()
    }
  }

  func close() async throws {}

  private func resumeWriteStartedContinuations() {
    let continuations = writeStartedContinuations
    writeStartedContinuations.removeAll()
    for continuation in continuations {
      continuation.resume()
    }
  }
}

private actor FailingSink: Sink {

  private let writeError: TestSinkError?
  private let closeError: TestSinkError?
  private var storage = Data()

  init(writeError: TestSinkError? = nil, closeError: TestSinkError? = nil) {
    self.writeError = writeError
    self.closeError = closeError
  }

  var bytesWritten: Int {
    get async throws { storage.count }
  }

  func write(data: Data) async throws {
    if let writeError {
      throw writeError
    }
    storage.append(data)
  }

  func close() async throws {
    if let closeError {
      throw closeError
    }
  }
}

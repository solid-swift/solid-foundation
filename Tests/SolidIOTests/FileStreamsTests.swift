//
//  FileStreamsTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 8/1/25.
//

@testable import SolidIO
import Foundation
import Testing


@Suite("File Streams Tests")
struct FileStreamsTests {

  @Test("Source reads completely")
  func sourceReadsCompletely() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    if !FileManager.default.createFile(atPath: fileURL.path, contents: nil) {
      throw CocoaError(.fileWriteUnknown)
    }

    let fileSize = 50 * 1024 * 1024
    let fileHandle = try FileHandle(forUpdating: fileURL)
    try fileHandle.truncate(atOffset: UInt64(fileSize))
    try fileHandle.seek(toOffset: 0)
    try fileHandle.close()

    let source = try FileSource(url: fileURL)

    for try await _ in source.buffers() {
      // read all buffers to test bytesRead
    }

    #expect(source.bytesRead == fileSize)
  }

  @Test("Source cancels")
  func sourceCancels() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    if !FileManager.default.createFile(atPath: fileURL.path, contents: nil) {
      throw CocoaError(.fileWriteUnknown)
    }

    let fileSize = 1024 * 1024
    let fileHandle = try FileHandle(forUpdating: fileURL)
    try fileHandle.truncate(atOffset: UInt64(fileSize))
    try fileHandle.seek(toOffset: 0)
    try fileHandle.close()

    let source = try FileSource(url: fileURL)

    let reader = Task {
      _ = try await source.read(max: 256 * 1024)
    }

    reader.cancel()
    await #expect(throws: CancellationError.self) {
      try await reader.value
    }

    #expect(source.bytesRead == 0)
    #expect(try source.fileHandle.offset() == 0)
  }

  @Test("Source cancels after start")
  func sourceCancelsAfterStart() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    if !FileManager.default.createFile(atPath: fileURL.path, contents: nil) {
      throw CocoaError(.fileWriteUnknown)
    }

    let fileSize = 1024 * 1024
    let fileHandle = try FileHandle(forUpdating: fileURL)
    try fileHandle.truncate(atOffset: UInt64(fileSize))
    try fileHandle.seek(toOffset: 0)
    try fileHandle.close()

    let readSize = 64 * 1024
    let source = try FileSource(url: fileURL)

    let reader = Task {
      while true {
        _ = try await source.read(max: readSize)
        withUnsafeCurrentTask { $0?.cancel() }
      }
    }

    await #expect(throws: CancellationError.self) {
      try await reader.value
    }

    #expect(source.bytesRead == readSize, "Data should have been read from source")
    #expect(try source.fileHandle.offset() == readSize)
  }

  @Test("Source continues after cancelled read")
  func sourceContinuesAfterCancel() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    if !FileManager.default.createFile(atPath: fileURL.path, contents: nil) {
      throw CocoaError(.fileWriteUnknown)
    }

    let fileSize = 1024 * 1024
    let fileHandle = try FileHandle(forUpdating: fileURL)
    try fileHandle.truncate(atOffset: UInt64(fileSize))
    try fileHandle.seek(toOffset: 0)
    try fileHandle.close()

    let readSize = 256 * 1024
    let source = try FileSource(url: fileURL)

    let readerA = Task {
      _ = try await source.read(max: readSize)
    }
    let readerB = Task {
      _ = try await source.read(max: readSize)
    }

    readerA.cancel()
    await #expect(throws: CancellationError.self) {
      try await readerA.value
    }

    #expect(source.bytesRead <= readSize)
    #expect(try source.fileHandle.offset() <= readSize)

    try await readerB.value
    try await source.close()

    #expect(source.bytesRead == readSize, "Second read should have succeeded")
    #expect(try source.fileHandle.offset() == readSize)
  }

  @Test("Sink cancels")
  func sinkCancels() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    if !FileManager.default.createFile(atPath: fileURL.path, contents: nil) {
      throw CocoaError(.fileWriteUnknown)
    }

    let data = Data(repeating: 0, count: 256 * 1024)
    let sink = try FileSink(url: fileURL)

    let writer = Task {
      try await sink.write(data: data)
    }

    writer.cancel()
    await #expect(throws: CancellationError.self) {
      try await writer.value
    }

    #expect(sink.bytesWritten == 0)
    #expect(try sink.fileHandle.offset() == 0)
  }

  @Test("Sink cancels after start")
  func sinkCancelsAfterStart() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    if !FileManager.default.createFile(atPath: fileURL.path, contents: nil) {
      throw CocoaError(.fileWriteUnknown)
    }

    let data = Data(repeating: 0, count: 64 * 1024)
    let sink = try FileSink(url: fileURL)

    let writer = Task {
      while true {
        try await sink.write(data: data)
        withUnsafeCurrentTask { $0?.cancel() }
      }
    }

    await #expect(throws: CancellationError.self) {
      try await writer.value
    }

    #expect(sink.bytesWritten == data.count, "Sink should have cancelled iteration")
    #expect(try sink.fileHandle.offset() == data.count)
  }

  @Test("Sink continues after cancelled write")
  func sinkContinuesAfterCancel() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    if !FileManager.default.createFile(atPath: fileURL.path, contents: nil) {
      throw CocoaError(.fileWriteUnknown)
    }

    let data = Data(repeating: 0, count: 256 * 1024)
    let sink = try FileSink(url: fileURL)

    let writerA = Task {
      try await sink.write(data: data)
    }
    let writerB = Task {
      try await sink.write(data: data)
    }

    writerA.cancel()
    await #expect(throws: CancellationError.self) {
      try await writerA.value
    }

    #expect(sink.bytesWritten <= data.count)
    #expect(try sink.fileHandle.offset() <= data.count)

    try await writerB.value
    try await sink.close()

    #expect(sink.bytesWritten == data.count, "Second write should have succeeded")
    #expect(try sink.fileHandle.offset() == data.count)
  }

  @Test("Invalid file source throws")
  func invalidFileSourceThrows() async throws {
    let error =
      #expect(throws: POSIXError.self) {
        _ = try FileSource(path: "/non-esixtent-file-\(Int.random(in: 0..<100000))")
      }
    #expect(error?.code == .ENOENT)
  }

  @Test("Invalid file sink throws")
  func invalidFileSinkThrows() async throws {
    let error =
      #expect(throws: POSIXError.self) {
        _ = try FileSink(path: "/non-esixtent-file-\(Int.random(in: 0..<100000))")
      }
    #expect(error?.code == .ENOENT)
  }
}

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

    let fileSize = 256 * 1024
    let fileHandle = try FileHandle(forUpdating: fileURL)
    try fileHandle.truncate(atOffset: UInt64(fileSize))
    try fileHandle.seek(toOffset: 0)
    try fileHandle.close()

    let source = try FileSource(url: fileURL)

    let reader = Task {
      for try await _ /* data */ in source.buffers(size: 3079) {
        // print("Read \(data.count) bytes of data")
      }
    }

    do {
      reader.cancel()
      try await reader.value
    } catch is CancellationError {}

    #expect(source.bytesRead == 0)
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

    let fileSize = 1 * 1024 * 1024
    let fileHandle = try FileHandle(forUpdating: fileURL)
    try fileHandle.truncate(atOffset: UInt64(fileSize))
    try fileHandle.seek(toOffset: 0)
    try fileHandle.close()

    let source = try FileSource(url: fileURL)

    let reader = Task {
      for try await _ in source.buffers(size: 133) {
        withUnsafeCurrentTask { $0!.cancel() }
      }
    }

    await #expect(throws: CancellationError.self) {
      try await reader.value
    }

    #expect(source.bytesRead > 0, "Data should have been read from source")
    #expect(source.bytesRead < fileSize, "Source should have cancelled iteration")
  }

  @Test("Source continues after cancel")
  func sourceContinuesAfterCancel() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    if !FileManager.default.createFile(atPath: fileURL.path, contents: nil) {
      throw CocoaError(.fileWriteUnknown)
    }

    let fileSize = 256 * 1024
    let fileHandle = try FileHandle(forUpdating: fileURL)
    try fileHandle.truncate(atOffset: UInt64(fileSize))
    try fileHandle.seek(toOffset: 0)
    try fileHandle.close()

    let source = try FileSource(url: fileURL)

    let reader = Task {
      for try await _ /* data */ in source.buffers(size: 3079) {
        // print("Read \(data.count) bytes of data")
      }
    }


    await #expect(throws: CancellationError.self) {
      reader.cancel()
      try await reader.value
    }

    #expect(source.bytesRead == 0)

    await #expect(throws: Never.self) {
      _ = try await source.read(exactly: 1000)
    }

    #expect(source.bytesRead == 1000)
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

    let source = DataSource(data: Data(count: 1024 * 1024))
    let sink = try FileSink(url: fileURL)

    let reader = Task {
      for try await buffer in source.buffers() {
        try await sink.write(data: buffer)
      }
    }

    await #expect(throws: CancellationError.self) {
      reader.cancel()
      try await reader.value
    }

    #expect(sink.bytesWritten == 0)
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

    let source = DataSource(data: Data(count: 1024 * 1024))
    let sink = try FileSink(url: fileURL)

    let firstWriteCompleted = AsyncStream<Void>.makeStream()

    let reader = Task {
      var isFirstWrite = true
      for try await buffer in source.buffers(size: 113) {
        try await sink.write(data: buffer)
        if isFirstWrite {
          isFirstWrite = false
          firstWriteCompleted.continuation.yield()
        }
      }
    }

    for await _ in firstWriteCompleted.stream {
      break
    }

    await #expect(throws: CancellationError.self) {
      reader.cancel()
      try await reader.value
    }

    #expect(sink.bytesWritten > 0, "Data should have been written to sink")
    #expect(sink.bytesWritten < source.data.count, "Sink should have cancelled iteration")
  }

  @Test("Sink continues after cancel")
  func sinkContinuesAfterCancel() async throws {
    var fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    if !FileManager.default.createFile(atPath: fileURL.path, contents: nil) {
      throw CocoaError(.fileWriteUnknown)
    }

    let source = DataSource(data: Data(count: 1024 * 1024))
    let sink = try FileSink(url: fileURL)

    let reader = Task {
      for try await buffer in source.buffers(size: 100) {
        try await sink.write(data: buffer)
      }
    }

    await #expect(throws: CancellationError.self) {
      reader.cancel()
      try await reader.value
    }

    #expect(sink.bytesWritten == 0)
    #expect(try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize == 0)

    try await sink.write(data: Data(count: 1000))
    try sink.close()

    #expect(sink.bytesWritten == 1000)
    fileURL.removeAllCachedResourceValues()
    #expect(try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize == 1000)
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

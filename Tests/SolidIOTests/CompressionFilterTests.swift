//
//  CompressionFilterTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 8/1/25.
//

@testable import SolidIO
import Foundation
import SwiftCompression
import Testing

@Suite("Compression Filter Tests") struct CompressionFilterTests {

  @Test("Round trip compression and decompression with Deflate/zlib") func roundTripZlib() async throws {
    let data = Data(repeating: 0x5A, count: (512 * 1024) + 3333)
    let sink = DataSink()

    let decompressingSink = try sink.decompressing(algorithm: .zlib)
    do {
      let compressingSource = try data.source().compressing(algorithm: .zlib)
      do {
        try await compressingSource.pipe(to: decompressingSink)

        try await compressingSource.close()
      } catch {
        try await compressingSource.close()
        throw error
      }

      try await decompressingSink.close()
    } catch {
      try await decompressingSink.close()
      throw error
    }

    #expect(sink.data == data)
  }

  @Test("Round trip compression and decompression with LZ4")
  func roundTripLz4() async throws {
    let data = Data(repeating: 0x5A, count: (512 * 1024) + 3333)
    let sink = DataSink()

    let decompressingSink = try sink.decompressing(algorithm: .lz4)
    do {
      let compressingSource = try data.source().compressing(algorithm: .lz4)
      do {
        try await compressingSource.pipe(to: decompressingSink)

        try await compressingSource.close()
      } catch {
        try await compressingSource.close()
        throw error
      }

      try await decompressingSink.close()
    } catch {
      try await decompressingSink.close()
      throw error
    }

    #expect(sink.data == data)
  }

  #if canImport(Compression)
  @Test("Round trip compression and decompression with LZFSE (Apple only)")
  @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
  func roundTripLzfse() async throws {
    let data = Data(repeating: 0x5A, count: (512 * 1024) + 3333)
    let sink = DataSink()

    let decompressingSink = try sink.decompressing(algorithm: .lzfse)
    do {
      let compressingSource = try data.source().compressing(algorithm: .lzfse)
      do {
        try await compressingSource.pipe(to: decompressingSink)

        try await compressingSource.close()
      } catch {
        try await compressingSource.close()
        throw error
      }

      try await decompressingSink.close()
    } catch {
      try await decompressingSink.close()
      throw error
    }

    #expect(sink.data == data)
  }

  @Test("Round trip compression and decompression with brotli (Apple only)")
  @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
  func roundTripBrotli() async throws {
    let data = Data(repeating: 0x5A, count: (512 * 1024) + 3333)
    let sink = DataSink()

    let decompressingSink = try sink.decompressing(algorithm: .brotli)
    do {
      let compressingSource = try data.source().compressing(algorithm: .brotli)
      do {
        try await compressingSource.pipe(to: decompressingSink)

        try await compressingSource.close()
      } catch {
        try await compressingSource.close()
        throw error
      }

      try await decompressingSink.close()
    } catch {
      try await decompressingSink.close()
      throw error
    }

    #expect(sink.data == data)
  }
  #endif
}

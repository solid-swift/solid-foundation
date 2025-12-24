//
//  CompressionFilterTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 8/1/25.
//

@testable import SolidIO
import Foundation
import Testing

@Suite("Compression Filter Tests")
struct CompressionFilterTests {

  @Test("Round trip compression and decompression")
  @available(macOS 26, *)
  func roundTrip() async throws {
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
}

//
//  BoxCipherFilterTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 8/1/25.
//

@testable import SolidIO
import Crypto
import Foundation
import Testing


@Suite("Box Cipher Filter Tests")
struct BoxCipherFilterTests {

  @Test("Round trip encryption and decryption")
  func roundTrip() async throws {
    let data = Data(repeating: 0x5A, count: (512 * 1024) + 3333)
    let sink = DataSink()

    let key = SymmetricKey(size: .bits256)

    let cipherSource =
      data.source()
      .applying(boxCipher: BoxCipherFilter.Algorithm.aesGcm, operation: BoxCipherFilter.Operation.seal, key: key)
    do {
      let cipherSink =
        sink
        .applying(boxCipher: BoxCipherFilter.Algorithm.aesGcm, operation: BoxCipherFilter.Operation.open, key: key)
      do {
        try await cipherSource.pipe(to: cipherSink, bufferSize: BufferedSource.segmentSize + 31)

        try await cipherSink.close()
      } catch {
        try await cipherSink.close()
        throw error
      }

      try await cipherSource.close()
    } catch {
      try await cipherSource.close()
      throw error
    }

    #expect(sink.data == data)
  }
}

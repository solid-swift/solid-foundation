//
//  HMACFilterTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 8/1/25.
//

@testable import SolidIO
import Foundation
import Crypto
import Testing


@Suite("HMAC Filter Tests")
struct HMACFilterTests {

  @Test("Round trip HMAC computation")
  func roundTrip() async throws {
    let data = Data(repeating: 0x5A, count: (512 * 1024) + 3333)
    let sink = DataSink()

    let key = SymmetricKey(size: .bits256)

    let (hmacSource, sourceResult) = data.source().authenticating(algorithm: .sha256, key: key)
    do {
      let (hmacSink, sinkResult) = sink.authenticating(algorithm: .sha256, key: key)
      do {
        try await hmacSource.pipe(to: hmacSink)

        try await hmacSink.close()
        try await hmacSource.close()

        #expect(sourceResult.digest == sinkResult.digest)
        #expect(sourceResult.digest == Data(HMAC<SHA256>.authenticationCode(for: data, using: key)))
      } catch {
        try await hmacSink.close()
        throw error
      }
    } catch {
      try await hmacSource.close()
      throw error
    }
  }
}

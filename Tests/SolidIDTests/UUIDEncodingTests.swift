//
//  UUIDEncodingTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/20/25.
//

import Testing
import SolidID


@Suite struct UUIDEncodingTests {

  @Test func base64Encoding() throws {
    let id = try #require(UUID(string: "56b4214b-848e-46a7-a8b0-e3554f3c9aca", using: .canonical))
    #expect(id.encode(using: .base64) == "VrQhS4SORqeosONVTzyayg")
  }

  @Test func base64Decoding() throws {
    let id = try #require(UUID(string: "VrQhS4SORqeosONVTzyayg", using: .base64))
    #expect(id.encode(using: .canonical) == "56b4214b-848e-46a7-a8b0-e3554f3c9aca")
  }

  @Test func base32CrockfordEncoding() throws {
    let id = try #require(UUID(string: "56b4214b-848e-46a7-a8b0-e3554f3c9aca", using: .canonical))
    #expect(id.encode(using: .base32Crockford) == "att22jw4hs3afa5gwdamyf4ts8")
  }

  @Test func base32CrockfordDecoding() throws {
    let id = try #require(UUID(string: "ATT22JW4HS3AFA5GWDAMYF4TS8", using: .base32Crockford))
    #expect(id.encode(using: .canonical) == "56b4214b-848e-46a7-a8b0-e3554f3c9aca")
  }

  @Test func base16Encoding() throws {
    let id = try #require(UUID(string: "56b4214b-848e-46a7-a8b0-e3554f3c9aca", using: .canonical))
    #expect(id.encode(using: .base16) == "56b4214b848e46a7a8b0e3554f3c9aca")
  }

  @Test func base16Decoding() throws {
    let id = try #require(UUID(string: "56b4214b848e46a7a8b0e3554f3c9aca", using: .base16))
    #expect(id.encode(using: .canonical) == "56b4214b-848e-46a7-a8b0-e3554f3c9aca")
  }

  @Test func canonicalEncoding() throws {
    let id = try #require(UUID(string: "56b4214b-848e-46a7-a8b0-e3554f3c9aca", using: .canonical))
    #expect(id.encode(using: .canonical) == "56b4214b-848e-46a7-a8b0-e3554f3c9aca")
  }

}

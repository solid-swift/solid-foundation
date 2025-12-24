//
//  UUIDEncodingTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/20/25.
//

import Testing
import SolidID


@Suite struct `UUIDEncoding Tests` {

  @Test func `base64 encoding`() throws {
    let id = try #require(UUID(string: "56b4214b-848e-46a7-a8b0-e3554f3c9aca", using: .canonical))
    #expect(id.encode(using: .base64) == "VrQhS4SORqeosONVTzyayg")
  }

  @Test func `base64 decoding`() throws {
    let id = try #require(UUID(string: "VrQhS4SORqeosONVTzyayg", using: .base64))
    #expect(id.encode(using: .canonical) == "56b4214b-848e-46a7-a8b0-e3554f3c9aca")
  }

  @Test func `base32 crockford encoding`() throws {
    let id = try #require(UUID(string: "56b4214b-848e-46a7-a8b0-e3554f3c9aca", using: .canonical))
    #expect(id.encode(using: .base32Crockford) == "att22jw4hs3afa5gwdamyf4ts8")
  }

  @Test func `base32 crockford decoding`() throws {
    let id = try #require(UUID(string: "ATT22JW4HS3AFA5GWDAMYF4TS8", using: .base32Crockford))
    #expect(id.encode(using: .canonical) == "56b4214b-848e-46a7-a8b0-e3554f3c9aca")
  }

  @Test func `base16 encoding`() throws {
    let id = try #require(UUID(string: "56b4214b-848e-46a7-a8b0-e3554f3c9aca", using: .canonical))
    #expect(id.encode(using: .base16) == "56b4214b848e46a7a8b0e3554f3c9aca")
  }

  @Test func `base16 decoding`() throws {
    let id = try #require(UUID(string: "56b4214b848e46a7a8b0e3554f3c9aca", using: .base16))
    #expect(id.encode(using: .canonical) == "56b4214b-848e-46a7-a8b0-e3554f3c9aca")
  }

  @Test func `canonical encoding`() throws {
    let id = try #require(UUID(string: "56b4214b-848e-46a7-a8b0-e3554f3c9aca", using: .canonical))
    #expect(id.encode(using: .canonical) == "56b4214b-848e-46a7-a8b0-e3554f3c9aca")
  }

}

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

  @Test func `base64 url encoding`() throws {
    let id = try #require(UUID(string: "56b4214b-848e-46a7-a8b0-e3554f3c9aca", using: .canonical))
    #expect(id.encode(using: .base64Url) == "VrQhS4SORqeosONVTzyayg")
  }

  @Test func `base64 url decoding`() throws {
    let id = try #require(UUID(string: "VrQhS4SORqeosONVTzyayg", using: .base64Url))
    #expect(id.encode(using: .canonical) == "56b4214b-848e-46a7-a8b0-e3554f3c9aca")
  }

  @Test func `base62 encoding`() throws {
    let id = try #require(UUID(string: "56b4214b-848e-46a7-a8b0-e3554f3c9aca", using: .canonical))
    #expect(id.encode(using: .base62) == "2dbeuDseqUyqFPSmfsA7a6")
  }

  @Test func `base62 decoding`() throws {
    let id = try #require(UUID(string: "2dbeuDseqUyqFPSmfsA7a6", using: .base62))
    #expect(id.encode(using: .canonical) == "56b4214b-848e-46a7-a8b0-e3554f3c9aca")
  }

  @Test func `base32 crockford encoding`() throws {
    let id = try #require(UUID(string: "56b4214b-848e-46a7-a8b0-e3554f3c9aca", using: .canonical))
    #expect(id.encode(using: .base32Crockford) == "ATT22JW4HS3AFA5GWDAMYF4TS8")
  }

  @Test func `base32 crockford decoding`() throws {
    let id = try #require(UUID(string: "att22jw4hs3afa5gwdamyf4ts8", using: .base32Crockford))
    #expect(id.encode(using: .canonical) == "56b4214b-848e-46a7-a8b0-e3554f3c9aca")
  }

  @Test func `base32 hex encoding`() throws {
    let id = try #require(UUID(string: "56b4214b-848e-46a7-a8b0-e3554f3c9aca", using: .canonical))
    #expect(id.encode(using: .base32Hex) == "AQQ22IS4HP3AFA5GSDAKUF4QP8")
  }

  @Test func `base32 hex decoding`() throws {
    let id = try #require(UUID(string: "aqq22is4hp3afa5gsdakuf4qp8", using: .base32Hex))
    #expect(id.encode(using: .canonical) == "56b4214b-848e-46a7-a8b0-e3554f3c9aca")
  }

  @Test func `base32 encoding`() throws {
    let id = try #require(UUID(string: "56b4214b-848e-46a7-a8b0-e3554f3c9aca", using: .canonical))
    #expect(id.encode(using: .base32) == "K22CCS4ERZDKPKFQ4NKU6PE2ZI")
  }

  @Test func `base32 decoding`() throws {
    let id = try #require(UUID(string: "k22ccs4erzdkpkfq4nku6pe2zi", using: .base32))
    #expect(id.encode(using: .canonical) == "56b4214b-848e-46a7-a8b0-e3554f3c9aca")
  }

  @Test func `base16 encoding`() throws {
    let id = try #require(UUID(string: "56b4214b-848e-46a7-a8b0-e3554f3c9aca", using: .canonical))
    #expect(id.encode(using: .base16) == "56B4214B848E46A7A8B0E3554F3C9ACA")
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

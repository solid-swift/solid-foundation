//
//  MediaRangesTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/28/26.
//

import HTTPTypes
@testable import SolidHTTP
import SolidNet
import Testing


@Suite("Media Ranges Tests")
struct MediaRangesTests {

  @Test("Parses accept media ranges")
  func parsesAcceptMediaRanges() throws {
    let ranges = try MediaRanges.parse("application/json, text/*;q=0.8, */*;q=0.1;ext=\"A,B\"")

    #expect(ranges.count == 3)
    #expect(ranges[0].mediaType == .json)
    #expect(ranges[0].quality == 1.0)
    #expect(ranges[1].mediaType == .anyText)
    #expect(ranges[1].quality == 0.8)
    #expect(ranges[2].mediaType == .any)
    #expect(ranges[2].quality == 0.1)
    #expect(ranges[2].acceptExtensions == ["ext": "\"A,B\""])
  }

  @Test("Negotiates by quality, specificity, and order")
  func negotiatesByQualitySpecificityAndOrder() throws {
    let ranges = try MediaRanges.parse("text/*;q=0.9, application/problem+json;q=0.8, */*;q=0")

    #expect(ranges.bestMatch(in: [.json, .html, .problemJSON]) == .html)
    #expect(ranges.bestMatch(in: [.json, .problemJSON]) == .problemJSON)
    #expect(ranges.bestMatch(in: [.cbor]) == nil)
  }

  @Test("Rejects invalid quality values")
  func rejectsInvalidQualityValues() {
    #expect(throws: MediaRange.Error.self) {
      try MediaRanges.parse("application/json;q=1.5")
    }
    #expect(throws: MediaRange.Error.self) {
      try MediaRanges.parse("application/json;q=bad")
    }
  }

  @Test("Serializes media ranges")
  func serializesMediaRanges() throws {
    let ranges = MediaRanges([
      MediaRange(.json),
      MediaRange(.anyText, quality: 0.8),
      MediaRange(.any, quality: 0.1, acceptExtensions: ["ext": "value"]),
    ])

    #expect(ranges.serialized() == "application/json,text/*;q=0.8,*/*;q=0.1;ext=value")
  }

  @Test("Integrates with HTTPFields")
  func integratesWithHTTPFields() throws {
    var fields = HTTPFields()
    fields.setContentType(.problemJSON.with(parameter: "charset", value: "utf-8"))
    fields.setAccept(MediaRanges([MediaRange(.json), MediaRange(.cbor, quality: 0.8)]))

    #expect(try fields.requireContentType() == MediaType.problemJSON.with(parameter: "charset", value: "utf-8"))
    #expect(try fields.contentType()?.serialized == "application/problem+json;charset=utf-8")
    #expect(try fields.acceptMediaRanges().bestMatch(in: [.cbor, .json]) == .json)
    #expect(fields[.contentType] == "application/problem+json;charset=utf-8")
    #expect(fields[.accept] == "application/json,application/cbor;q=0.8")
  }

  @Test("Content-Type rejects accept-only q metadata")
  func contentTypeRejectsAcceptOnlyQualityMetadata() {
    var fields = HTTPFields()
    fields[.contentType] = "application/json;q=0.5"

    #expect(throws: MediaType.Error.self) {
      try fields.requireContentType()
    }
  }

}

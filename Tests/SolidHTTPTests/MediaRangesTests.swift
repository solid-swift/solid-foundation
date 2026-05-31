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
    #expect(ranges[2].acceptExtensions == ["ext": "A,B"])
    #expect(ranges.serialized() == "application/json,text/*;q=0.8,*/*;q=0.1;ext=\"A,B\"")
    #expect(try MediaRanges.parse(ranges.serialized()) == ranges)
  }

  @Test("Negotiates by quality, specificity, and order")
  func negotiatesByQualitySpecificityAndOrder() throws {
    let ranges = try MediaRanges.parse("text/*;q=0.9, application/problem+json;q=0.8, */*;q=0")

    #expect(ranges.bestMatch(in: [.json, .html, .problemJSON]) == .html)
    #expect(ranges.bestMatch(in: [.json, .problemJSON]) == .problemJSON)
    #expect(ranges.bestMatch(in: [.cbor]) == nil)
  }

  @Test("Uses the most specific matching range quality")
  func usesMostSpecificMatchingRangeQuality() throws {
    let ranges = try MediaRanges.parse("application/*;q=1, application/json;q=0.5, text/html;q=0.7")

    #expect(ranges.bestMatch(in: [.json, .html]) == .html)
  }

  @Test("Rejects a media type with zero quality in its most specific range")
  func rejectsZeroQualityMostSpecificRange() throws {
    let ranges = try MediaRanges.parse("*/*;q=0.5, application/json;q=0")

    #expect(ranges.bestMatch(in: [.json]) == nil)
    #expect(ranges.bestMatch(in: [.json, .html]) == .html)
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
    let wildcard = MediaRange(.any, quality: 0.1, acceptExtensions: ["ext": "A,B"])
    let ranges = MediaRanges([
      MediaRange(.json),
      MediaRange(.anyText, quality: 0.8),
      wildcard,
    ])

    #expect(wildcard.serialized == "*/*;q=0.1;ext=\"A,B\"")
    #expect(ranges.serialized() == "application/json,text/*;q=0.8,*/*;q=0.1;ext=\"A,B\"")
    #expect(try MediaRanges.parse(ranges.serialized()) == ranges)
  }

  @Test("Provides format family ranges")
  func providesFormatFamilyRanges() {
    #expect(MediaRanges.json.serialized() == "application/json,*/*+json")
    #expect(MediaRanges.xml.serialized() == "application/xml,*/*+xml")
    #expect(MediaRanges.cbor.serialized() == "application/cbor,*/*+cbor")
    #expect(MediaRanges.json.bestMatch(in: [.problemJSON]) == .problemJSON)
    #expect(MediaRanges.json.bestMatch(in: [.json, .problemJSON]) == .json)
    #expect(MediaRanges.json.bestMatch(in: [.octetStream]) == nil)
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

  @Test("Require Content-Type reports missing header")
  func requireContentTypeReportsMissingHeader() {
    let fields = HTTPFields()

    #expect(throws: HTTPFields.MediaTypeError.missingContentType) {
      try fields.requireContentType()
    }
  }

}

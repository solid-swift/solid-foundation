//
//  MediaTypeTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/28/26.
//

@testable import SolidNet
import Foundation
import Testing


@Suite("Media Type Tests")
struct MediaTypeTests {

  @Test("Parses and serializes canonical media type")
  func parsesAndSerializesCanonicalMediaType() throws {
    let mediaType = try #require(MediaType("APPLICATION/VND.API+JSON ; CHARSET=UTF-8 ; VERSION=Beta"))

    #expect(mediaType.type == .application)
    #expect(mediaType.tree == .vendor)
    #expect(mediaType.subtype == "api")
    #expect(mediaType.suffix == "json")
    #expect(mediaType.parameter("charset") == "utf-8")
    #expect(mediaType.parameter("version") == "Beta")
    #expect(mediaType.serialized == "application/vnd.api+json;charset=utf-8;version=Beta")
    #expect(mediaType.description == mediaType.serialized)
  }

  @Test("Preserves case-sensitive parameter values")
  func preservesCaseSensitiveParameterValues() throws {
    let mediaType = try #require(MediaType("multipart/form-data; boundary=\"AaB03x,Still;Boundary\""))

    #expect(mediaType.parameter("boundary") == "AaB03x,Still;Boundary")
    #expect(mediaType.serialized == "multipart/form-data;boundary=AaB03x,Still;Boundary")
  }

  @Test("Rejects invalid media types")
  func rejectsInvalidMediaTypes() {
    #expect(MediaType("") == nil)
    #expect(MediaType("application") == nil)
    #expect(MediaType("application/") == nil)
    #expect(MediaType("/json") == nil)
    #expect(MediaType("application/json;missing-value") == nil)
    #expect(MediaType("application/json;q=0.5") == nil)
  }

  @Test("Matches compatible media types")
  func matchesCompatibleMediaTypes() throws {
    let problem = try #require(MediaType("application/problem+json;charset=utf-8"))
    let jsonStructured = MediaType.anyStructuredJSON
    let jsonWithCharset = MediaType.json.with(parameter: "charset", value: "utf-8")
    let jsonWithOtherCharset = MediaType.json.with(parameter: "charset", value: "utf-16")

    #expect(problem.matches(jsonStructured))
    #expect(jsonStructured.matches(problem))
    #expect(MediaType.any.matches(problem))
    #expect(MediaType.anyText.matches(.html))
    #expect(jsonWithCharset.matches(.json))
    #expect(jsonWithCharset.matches(MediaType.json.with(parameter: "charset", value: "UTF-8")))
    #expect(!jsonWithCharset.matches(jsonWithOtherCharset))
    #expect(!MediaType.anyStructuredJSON.matches(.json))
    #expect(!MediaType.anyStructuredJSON.matches(.octetStream))
    #expect(!MediaType.anyStructuredXML.matches(problem))
  }

  @Test("Codable round trips as serialized string")
  func codableRoundTripsAsSerializedString() throws {
    let mediaType = MediaType.problemJSON.with(parameter: "charset", value: "utf-8")
    let encoded = try JSONEncoder().encode(mediaType)
    let decoded = try JSONDecoder().decode(MediaType.self, from: encoded)
    let encodedString = try #require(
      try JSONSerialization.jsonObject(with: encoded, options: [.fragmentsAllowed]) as? String
    )

    #expect(encodedString == "application/problem+json;charset=utf-8")
    #expect(decoded == mediaType)
  }

  @Test("Curated constants serialize to registered values")
  func curatedConstantsSerializeToRegisteredValues() {
    #expect(MediaType.json.serialized == "application/json")
    #expect(MediaType.cborSequence.serialized == "application/cbor-seq")
    #expect(MediaType.problemJSON.serialized == "application/problem+json")
    #expect(MediaType.conciseProblemCBOR.serialized == "application/concise-problem-details+cbor")
    #expect(MediaType.formUrlEncoded.serialized == "application/x-www-form-urlencoded")
    #expect(MediaType.svg.serialized == "image/svg+xml")
    #expect(MediaType.mp4Audio.serialized == "audio/mp4")
    #expect(MediaType.mp4.serialized == "video/mp4")
    #expect(MediaType.woff2.serialized == "font/woff2")
    #expect(MediaType.gltfBinary.serialized == "model/gltf-binary")
    #expect(MediaType.pkcs8Encrypted.serialized == "application/pkcs8-encrypted")
    #expect(MediaType.x509CACertificate.serialized == "application/x-x509-ca-cert")
    #expect(MediaType.anyStructuredJSON.serialized == "*/*+json")
    #expect(MediaType.anyStructuredCBOR.serialized == "*/*+cbor")
  }

}

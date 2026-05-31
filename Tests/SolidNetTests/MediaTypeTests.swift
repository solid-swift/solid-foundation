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
    #expect(mediaType.suffix == .json)
    #expect(mediaType.parameter("charset") == "utf-8")
    #expect(mediaType.parameter("version") == "Beta")
    #expect(mediaType.serialized == "application/vnd.api+json;charset=utf-8;version=Beta")
    #expect(mediaType.description == mediaType.serialized)
  }

  @Test("Parses arbitrary well-formed media types")
  func parsesArbitraryWellFormedMediaTypes() throws {
    let haptics = try #require(MediaType("haptics/ivs"))
    let unknownTree = try #require(MediaType("application/foo.bar+baz"))
    let multiPlus = try #require(MediaType("application/foo+bar+baz"))
    let vendor = try #require(MediaType("application/vnd.example+json"))
    let personal = try #require(MediaType("application/prs.example"))
    let unregistered = try #require(MediaType("application/x.example"))
    let obsolete = try #require(MediaType("application/x-example"))

    #expect(haptics.type == "haptics")
    #expect(haptics.tree == .standard)
    #expect(haptics.subtype == "ivs")
    #expect(haptics.serialized == "haptics/ivs")
    #expect(unknownTree.tree == "foo.")
    #expect(unknownTree.subtype == "bar")
    #expect(unknownTree.suffix == "baz")
    #expect(unknownTree.serialized == "application/foo.bar+baz")
    #expect(multiPlus.tree == .standard)
    #expect(multiPlus.subtype == "foo+bar")
    #expect(multiPlus.suffix == "baz")
    #expect(multiPlus.serialized == "application/foo+bar+baz")
    #expect(vendor.tree == .vendor)
    #expect(personal.tree == .personal)
    #expect(unregistered.tree == .unregistered)
    #expect(obsolete.tree == .obsolete)
  }

  @Test("Preserves case-sensitive parameter values")
  func preservesCaseSensitiveParameterValues() throws {
    let mediaType = try #require(MediaType("multipart/form-data; boundary=\"AaB03x,Still;Boundary\""))
    let reparsed = try #require(MediaType(mediaType.serialized))

    #expect(mediaType.parameter("boundary") == "AaB03x,Still;Boundary")
    #expect(mediaType.serialized == "multipart/form-data;boundary=\"AaB03x,Still;Boundary\"")
    #expect(reparsed == mediaType)
  }

  @Test("Serializes constructed parameter values safely")
  func serializesConstructedParameterValuesSafely() throws {
    let mediaType = MediaType.multipartFormData.with(parameter: "boundary", value: "AaB03x,Still;Boundary")
    let reparsed = try #require(MediaType(mediaType.serialized))

    #expect(mediaType.serialized == "multipart/form-data;boundary=\"AaB03x,Still;Boundary\"")
    #expect(reparsed == mediaType)

    let tokenValue = MediaType.plainText.with(parameter: "version", value: "Beta")
    #expect(tokenValue.serialized == "text/plain;version=Beta")
  }

  @Test("Escapes quoted parameter values")
  func escapesQuotedParameterValues() throws {
    let mediaType = MediaType.plainText.with(parameter: "note", value: #"quoted "value" \ marker"#)
    let reparsed = try #require(MediaType(mediaType.serialized))

    #expect(mediaType.serialized == #"text/plain;note="quoted \"value\" \\ marker""#)
    #expect(reparsed.parameter("note") == #"quoted "value" \ marker"#)
    #expect(reparsed == mediaType)
  }

  @Test("Rejects invalid media types")
  func rejectsInvalidMediaTypes() {
    #expect(MediaType("") == nil)
    #expect(MediaType("application") == nil)
    #expect(MediaType("application/") == nil)
    #expect(MediaType("/json") == nil)
    #expect(MediaType("application/json;missing-value") == nil)
    #expect(MediaType("application/json;q=0.5") == nil)
    #expect(MediaType("application/foo+") == nil)
    #expect(MediaType("application/foo.") == nil)
    #expect(MediaType("application/fo o") == nil)
    #expect(MediaType("*/json") == nil)
    #expect(MediaType("application/vnd.*") == nil)
    #expect(MediaType("application/json;charset =utf-8") == nil)
    #expect(MediaType("application/json;charset= utf-8") == nil)
    #expect(MediaType("application/json;charset=utf-8;CHARSET=ascii") == nil)
    #expect(MediaType("application/foo;note=\"line\rbreak\"") == nil)
    #expect(MediaType("application/foo;note=\"bad\\\rpair\"") == nil)
    #expect(MediaType("application/foo;note=\"emoji\u{1F600}\"") == nil)
  }

  @Test("Matches compatible media types")
  func matchesCompatibleMediaTypes() throws {
    let problem = try #require(MediaType("application/problem+json;charset=utf-8"))
    let vendorText = MediaType(type: .text, tree: .vendor, subtype: "example")
    let jsonStructured = MediaType.anyStructuredJSON
    let jsonWithCharset = MediaType.json.with(parameter: "charset", value: "utf-8")
    let jsonWithOtherCharset = MediaType.json.with(parameter: "charset", value: "utf-16")

    #expect(problem.matches(jsonStructured))
    #expect(jsonStructured.matches(problem))
    #expect(MediaType.any.matches(.jsonAPI))
    #expect(MediaType.jsonAPI.matches(.any))
    #expect(jsonStructured.matches(.jsonAPI))
    #expect(MediaType.jsonAPI.matches(jsonStructured))
    #expect(MediaType.anyText.matches(vendorText))
    #expect(MediaType.any.matches(problem))
    #expect(MediaType.anyText.matches(.html))
    #expect(jsonWithCharset.matches(.json))
    #expect(jsonWithCharset.matches(MediaType.json.with(parameter: "charset", value: "UTF-8")))
    #expect(!jsonWithCharset.matches(jsonWithOtherCharset))
    #expect(!MediaType.anyStructuredJSON.matches(.json))
    #expect(!MediaType.anyStructuredJSON.matches(.octetStream))
    #expect(!MediaType.anyStructuredXML.matches(problem))
  }

  @Test("Codable round trips media type component values")
  func codableRoundTripsMediaTypeComponents() throws {
    let kind = try JSONDecoder().decode(MediaType.Kind.self, from: Data(#""HAPTICS""#.utf8))
    let tree = try JSONDecoder().decode(MediaType.Tree.self, from: Data(#""foo.""#.utf8))
    let suffix = try JSONDecoder().decode(MediaType.Suffix.self, from: Data(#""BAZ""#.utf8))
    let constructed = MediaType(type: kind, tree: tree, subtype: "bar", suffix: suffix)
    let reparsed = try #require(MediaType(constructed.serialized))

    #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(kind), options: [.fragmentsAllowed]) as? String == "haptics")
    #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(tree), options: [.fragmentsAllowed]) as? String == "foo.")
    #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(suffix), options: [.fragmentsAllowed]) as? String == "baz")
    #expect(constructed.serialized == "haptics/foo.bar+baz")
    #expect(reparsed == constructed)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(MediaType.Kind.self, from: Data(#""bad value""#.utf8))
    }
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(MediaType.Tree.self, from: Data(#""foo""#.utf8))
    }
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(MediaType.Suffix.self, from: Data(#""bad+suffix""#.utf8))
    }
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
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(MediaType.self, from: Data(#""application/json;q=0.5""#.utf8))
    }
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
    #expect(MediaType.brotli.serialized == "application/x-brotli")
    #expect(MediaType.pkcs8Encrypted.serialized == "application/pkcs8-encrypted")
    #expect(MediaType.x509CACertificate.serialized == "application/x-x509-ca-cert")
    #expect(MediaType.anyStructuredJSON.serialized == "*/*+json")
    #expect(MediaType.anyStructuredCBOR.serialized == "*/*+cbor")
  }

}

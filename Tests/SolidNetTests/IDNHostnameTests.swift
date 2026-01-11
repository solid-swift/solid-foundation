//
//  IDNHostnameTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

@testable import SolidNet
import Testing


@Suite("IDN Hostname Tests")
final class IDNHostnameTests {

  // MARK: - Basic Validation

  @Test("Valid hostnames")
  func validHostnames() throws {
    // Test valid ASCII hostnames
    let example = IDNHostname.parse(string: "example.com")
    let exampleValue = try #require(example?.encoded, "Failed to parse example.com")
    #expect(exampleValue == "example.com")

    let subExample = IDNHostname.parse(string: "sub.example.com")
    let subValue = try #require(subExample?.encoded, "Failed to parse sub.example.com")
    #expect(subValue == "sub.example.com")

    let longHostname = IDNHostname.parse(string: "a.b.c.d.e.f.g.h.i.j.k.l.m.n.o.p.q.r.s.t.u.v.w.x.y.z")
    let longValue = try #require(longHostname?.encoded, "Failed to parse long hostname")
    #expect(longValue == "a.b.c.d.e.f.g.h.i.j.k.l.m.n.o.p.q.r.s.t.u.v.w.x.y.z")

    // Test valid IDN hostnames
    let idnHostname = IDNHostname.parse(string: "xn--bcher-kva.example")
    let idnValue = try #require(idnHostname?.encoded, "Failed to parse IDN hostname")
    #expect(idnValue == "xn--bcher-kva.example")

    let nestedIdn = IDNHostname.parse(string: "xn--bcher-kva.xn--bcher-kva.example")
    let nestedValue = try #require(nestedIdn?.encoded, "Failed to parse nested IDN hostname")
    #expect(nestedValue == "xn--bcher-kva.xn--bcher-kva.example")

    // Test valid hostnames with trailing dot
    let trailingDot = IDNHostname.parse(string: "example.com.")
    let trailingValue = try #require(trailingDot?.encoded, "Failed to parse hostname with trailing dot")
    #expect(trailingValue == "example.com")
  }

  @Test("Invalid hostnames")
  func invalidHostnames() {
    // Test hostnames that are too long
    let longString = String(repeating: "a", count: 256)
    #expect(IDNHostname.parse(string: longString) == nil)

    // Test hostnames with invalid characters
    #expect(IDNHostname.parse(string: "example@.com") == nil)
    #expect(IDNHostname.parse(string: "example!.com") == nil)
    #expect(IDNHostname.parse(string: "example#.com") == nil)

    // Test hostnames with invalid label lengths
    let longLabel = String(repeating: "a", count: 64)
    #expect(IDNHostname.parse(string: "\(longLabel).com") == nil)

    // Test empty hostname
    #expect(IDNHostname.parse(string: "") == nil)

    // Test hostname with empty labels
    #expect(IDNHostname.parse(string: "example..com") == nil)
    #expect(IDNHostname.parse(string: ".example.com") == nil)
  }

  // MARK: - Label Validation

  @Test("Valid labels")
  func validLabels() throws {
    // Test valid ASCII labels
    let simpleLabel = IDNHostname.parse(string: "a.example")
    let simpleValue = try #require(simpleLabel?.encoded, "Failed to parse simple label")
    #expect(simpleValue == "a.example")

    let hyphenLabel = IDNHostname.parse(string: "a-b.example")
    let hyphenValue = try #require(hyphenLabel?.encoded, "Failed to parse hyphen label")
    #expect(hyphenValue == "a-b.example")

    let numericLabel = IDNHostname.parse(string: "a1.example")
    let numericValue = try #require(numericLabel?.encoded, "Failed to parse numeric label")
    #expect(numericValue == "a1.example")

    // Test valid IDN labels
    let idnLabel = IDNHostname.parse(string: "xn--bcher-kva.example")
    let idnValue = try #require(idnLabel?.encoded, "Failed to parse IDN label")
    #expect(idnValue == "xn--bcher-kva.example")

    let nestedIdnLabel = IDNHostname.parse(string: "xn--bcher-kva.xn--bcher-kva.example")
    let nestedValue = try #require(nestedIdnLabel?.encoded, "Failed to parse nested IDN label")
    #expect(nestedValue == "xn--bcher-kva.xn--bcher-kva.example")
  }

  @Test("Invalid labels")
  func invalidLabels() {
    // Test labels that start or end with hyphen
    #expect(IDNHostname.parse(string: "-example.com") == nil)
    #expect(IDNHostname.parse(string: "example-.com") == nil)

    // Test labels with consecutive hyphens
    #expect(IDNHostname.parse(string: "exa--mple.com") == nil)

    // Test labels with invalid characters
    #expect(IDNHostname.parse(string: "ex@mple.com") == nil)
    #expect(IDNHostname.parse(string: "ex!mple.com") == nil)
  }

  // MARK: - Parameterized

  @Test(
    "Valid hostname lengths",
    arguments: [
      "a.b",
      String(repeating: "a", count: 63) + "." + String(repeating: "b", count: 63) + "."
        + String(repeating: "c", count: 63) + "." + String(repeating: "d", count: 63) + ".com",
    ]
  )
  func validHostnameLengths(hostname: String) throws {
    let result = IDNHostname.parse(string: hostname)
    let value = try #require(result?.encoded, "Failed for hostname: \(hostname)")
    #expect(value == hostname, "Value mismatch for hostname: \(hostname)")
  }

  @Test(
    "Valid label lengths",
    arguments: [
      "a.example.com",
      String(repeating: "a", count: 63) + ".com",
    ]
  )
  func validLabelLengths(hostname: String) throws {
    let result = IDNHostname.parse(string: hostname)
    let value = try #require(result?.encoded, "Failed for hostname: \(hostname)")
    #expect(value == hostname, "Value mismatch for hostname: \(hostname)")
  }

  // MARK: - Edge Cases

  @Test("Edge cases")
  func edgeCases() throws {
    // Test single label
    let localhost = IDNHostname.parse(string: "localhost")
    let localhostValue = try #require(localhost?.encoded, "Failed to parse localhost")
    #expect(localhostValue == "localhost")

    // Test root domain
    let root = IDNHostname.parse(string: ".", allowRoot: true)
    let rootValue = try #require(root?.encoded, "Failed to parse root domain")
    #expect(rootValue == "")

    // Test hostname with all valid characters
    let mixedChars = IDNHostname.parse(string: "a1-b2-c3.example")
    let mixedValue = try #require(mixedChars?.encoded, "Failed to parse mixed character hostname")
    #expect(mixedValue == "a1-b2-c3.example")

    // Test hostname with mixed case
    let mixedCase = IDNHostname.parse(string: "ExAmPlE.CoM")
    let caseValue = try #require(mixedCase?.encoded, "Failed to parse mixed case hostname")
    #expect(caseValue == "ExAmPlE.CoM")
  }

  // MARK: - IDN Specific

  @Test("IDN validation")
  func idnValidation() throws {
    // Test valid A-labels (Punycode)
    let validPunycode = IDNHostname.parse(string: "xn--bcher-kva.example")
    let punycodeValue = try #require(validPunycode?.encoded, "Failed to parse valid Punycode")
    #expect(punycodeValue == "xn--bcher-kva.example")

    let nestedValidPunycode = IDNHostname.parse(string: "xn--bcher-kva.xn--bcher-kva.example")
    let nestedValue = try #require(nestedValidPunycode?.encoded, "Failed to parse nested valid Punycode")
    #expect(nestedValue == "xn--bcher-kva.xn--bcher-kva.example")

    // Test invalid A-labels
    #expect(IDNHostname.parse(string: "xn--.example") == nil, "Should reject empty A-label")
    #expect(IDNHostname.parse(string: "xn---.example") == nil, "Should reject A-label with only hyphen")
    #expect(IDNHostname.parse(string: "xn--a-.example") == nil, "Should reject A-label ending with hyphen")
    #expect(
      IDNHostname.parse(string: "xn--a--b.example") == nil,
      "Should reject A-label with consecutive hyphens"
    )
  }

}

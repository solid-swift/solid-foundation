//
//  HostnameTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/31/25.
//

@testable import SolidNet
import Testing


@Suite("Hostname Tests")
final class HostnameTests {

  // MARK: - Valid

  @Test("Valid hostnames should parse successfully")
  func validHostname() {
    // Test standard hostnames
    #expect(Hostname.parse(string: "example.com") != nil)
    #expect(Hostname.parse(string: "sub.example.com") != nil)
    #expect(Hostname.parse(string: "a.b.c.d.e.f.g") != nil)
    #expect(Hostname.parse(string: "example.com.") != nil)    // With trailing dot
    #expect(Hostname.parse(string: "xn--example-9ua.com") != nil)    // Punycode
    #expect(Hostname.parse(string: "xn--bcher-kva.ch") != nil)    // Punycode
  }

  @Test("Hostnames with hyphens should parse successfully")
  func validHostnameWithHyphens() {
    #expect(Hostname.parse(string: "my-example.com") != nil)
    #expect(Hostname.parse(string: "my-example-1.com") != nil)
    #expect(Hostname.parse(string: "my-example-1-2.com") != nil)
  }

  @Test("Hostnames with numbers should parse successfully")
  func validHostnameWithNumbers() {
    #expect(Hostname.parse(string: "example1.com") != nil)
    #expect(Hostname.parse(string: "1example.com") != nil)
    #expect(Hostname.parse(string: "example1.example2.com") != nil)
  }

  // MARK: - Invalid

  @Test("Hostnames exceeding maximum length should fail to parse")
  func invalidHostnameLength() {
    let longString = String(repeating: "a", count: Hostname.maxLength + 1)
    #expect(Hostname.parse(string: longString) == nil)
  }

  @Test("Hostnames with invalid labels should fail to parse")
  func invalidHostnameLabels() {
    #expect(Hostname.parse(string: "") == nil)    // Empty string
    #expect(Hostname.parse(string: ".") == nil)    // Just a dot
    #expect(Hostname.parse(string: "example..com") == nil)    // Double dot
    #expect(Hostname.parse(string: "-example.com") == nil)    // Leading hyphen
    #expect(Hostname.parse(string: "example-.com") == nil)    // Trailing hyphen
    #expect(Hostname.parse(string: "example.com-") == nil)    // Trailing hyphen
    #expect(Hostname.parse(string: "example@.com") == nil)    // Invalid character
    #expect(Hostname.parse(string: "example.com/") == nil)    // Invalid character
  }

  @Test("Hostnames with xn-- labels should parse if they follow LDH rules")
  func xnLabels() {
    // Valid xn-- labels that follow LDH rules
    #expect(Hostname.parse(string: "xn--example.com") != nil)    // Valid LDH label
    #expect(Hostname.parse(string: "xn--example-1.com") != nil)    // Valid LDH label with hyphen and number
    #expect(Hostname.parse(string: "xn--example1.com") != nil)    // Valid LDH label with number

    // Invalid xn-- labels that don't follow LDH rules
    #expect(Hostname.parse(string: "xn--.com") == nil)    // Empty label
    #expect(Hostname.parse(string: "xn--example-.com") == nil)    // Trailing hyphen
    #expect(Hostname.parse(string: "xn--example@.com") == nil)    // Invalid character
  }

  // MARK: - Properties

  @Test("Hostname properties should be correctly set")
  func hostnameProperties() throws {
    let hostname = try #require(Hostname.parse(string: "sub.example.com"))

    #expect(hostname.labels == ["sub", "example", "com"])
    #expect(hostname.encoded == "sub.example.com")
  }

  @Test("Hostname with trailing dot should be handled correctly")
  func hostnameWithTrailingDot() throws {
    let hostname = try #require(Hostname.parse(string: "sub.example.com."))

    #expect(hostname.labels == ["sub", "example", "com"])
    #expect(hostname.encoded == "sub.example.com")
  }

  // MARK: - Edge Cases

  @Test("Single label hostnames should parse successfully")
  func singleLabelHostname() {
    #expect(Hostname.parse(string: "localhost") != nil)
    #expect(Hostname.parse(string: "localhost.") != nil)
  }

  @Test("Maximum label length should be enforced")
  func maximumLabelLength() {
    // Test label with maximum length (63 characters)
    let maxLabel = String(repeating: "a", count: 63)
    #expect(Hostname.parse(string: "\(maxLabel).com") != nil)

    // Test label exceeding maximum length (64 characters)
    let tooLongLabel = String(repeating: "a", count: 64)
    #expect(Hostname.parse(string: "\(tooLongLabel).com") == nil)
  }

  @Test("Hostnames should be case-insensitive")
  func mixedCaseHostname() {
    #expect(Hostname.parse(string: "EXAMPLE.COM") != nil)
    #expect(Hostname.parse(string: "Example.Com") != nil)
    #expect(Hostname.parse(string: "exAmPlE.cOm") != nil)
  }
}

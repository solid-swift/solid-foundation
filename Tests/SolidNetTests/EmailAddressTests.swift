//
//  EmailAddressTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

@testable import SolidNet
import Testing


@Suite("EmailAddress Tests")
final class EmailAddressTests {

  // MARK: - Initialization

  @Test(
    "Initialize with local and domain",
    arguments: [
      ("user", "example.com", "user@example.com"),
      ("user.name", "example.com", "user.name@example.com"),
      ("\\\"user name\\\"", "example.com", "\\\"user name\\\"@example.com"),
      ("user", "[192.168.0.1]", "user@[192.168.0.1]"),
    ]
  )
  func initWithComponents(local: String, domain: String, expected: String) {
    let m = EmailAddress(local: local, domain: domain)
    #expect(m.local == local)
    #expect(m.domain == domain)
    #expect(m.encoded == expected)
  }

  // MARK: - Formatting

  @Test("Encoding and description for simple address")
  func formattingSimple() {
    let m = EmailAddress(local: "user", domain: "example.com")
    #expect(m.encoded == "user@example.com")
    #expect("\(m)" == "user@example.com")
  }

  @Test("Quoted local part preserved in formatting")
  func formattingQuotedLocal() {
    let m = EmailAddress(local: "\"user name\"", domain: "example.com")
    #expect(m.encoded == "\"user name\"@example.com")
    #expect(m.description == "\"user name\"@example.com")
  }

  @Test("IPv4 domain-literal formatting")
  func formattingIPv4DomainLiteral() {
    let ipv4 = ["192","168","1","42"].joined(separator: ".")
    let domain = "[" + ipv4 + "]"
    let m = EmailAddress(local: "user", domain: domain)
    #expect(m.encoded == "user@" + domain)
  }

  @Test("IPv6 domain-literal formatting")
  func formattingIPv6DomainLiteral() {
    func ip6(_ parts: [String]) -> String { parts.joined(separator: ":") }
    let v6 = "IPv6:" + ip6(["2001","db8","","1"]) // 2001:db8::1
    let domain = "[" + v6 + "]"
    let m = EmailAddress(local: "user", domain: domain)
    #expect(m.description == "user@" + domain)
  }

  @Test("Parsing preserves formatting on output")
  func formattingFromParse() throws {
    let email = "user+tag@sub.example.com"
    let m = try #require(EmailAddress.parse(string: email))
    #expect(m.encoded == email)
    #expect("\(m)" == email)
  }

  // MARK: - Parsing

  @Test(
    "Valid Mailbox Parsing",
    arguments: [
      // Simple valid addresses
      "user@example.com",
      "user.name@example.com",
      "user+tag@example.com",
      "user@subdomain.example.com",
      "user@[127.0.0.1]",

      // Quoted strings in local part
      "\"user name\"@example.com",
      "\"user@name\"@example.com",
      "\"user\\\\name\"@example.com",
      "\"user\\\"name\"@example.com",

      // Special characters in local part
      "!#$%&'*+-/=?^_`{|}~@example.com",
      "user.name!#$%&'*+-/=?^_`{|}~@example.com",

      // Domain literals
      "user@[IPv6:2001:db8::1]",
      "user@[IPv6:2001:db8:85a3:8d3:1319:8a2e:370:7348]",

      // Long but valid addresses
      "a".padding(toLength: 64, withPad: "a", startingAt: 0) + "@example.com",
      "user@" + "a".padding(toLength: 63, withPad: "a", startingAt: 0) + "."
        + "b".padding(toLength: 63, withPad: "b", startingAt: 0) + "."
        + "c".padding(toLength: 63, withPad: "c", startingAt: 0) + "."
        + "d".padding(toLength: 59, withPad: "d", startingAt: 0) + ".com",
    ]
  )
  func validMailboxParsing(address: String) {
    #expect(EmailAddress.parse(string: address) != nil, "Should parse valid address: \(address)")
  }

  @Test(
    "Invalid Mailbox Parsing",
    arguments: [
      // Missing @
      "userexample.com",
      // Missing local part
      "@example.com",
      // Missing domain
      "user@",
      // Empty string
      "",
      // Multiple @
      "user@name@example.com",
      // Invalid characters in local part
      "user,name@example.com",
      "user;name@example.com",
      "user:name@example.com",
      "user<name@example.com",
      "user>name@example.com",
      // Invalid domain format
      "user@example..com",
      "user@.example.com",
      "user@example.com.",
      // Invalid domain literal
      "user@[invalid]",
      "user@[127.0.0.1",
      "user@127.0.0.1]",
      // Too long local part (>64 chars)
      "a".padding(toLength: 65, withPad: "a", startingAt: 0) + "@example.com",
      // Too long domain (>255 chars)
      "user@" + "a".padding(toLength: 63, withPad: "a", startingAt: 0) + "."
        + "b".padding(toLength: 63, withPad: "b", startingAt: 0) + "."
        + "c".padding(toLength: 63, withPad: "c", startingAt: 0) + "."
        + "d".padding(toLength: 63, withPad: "d", startingAt: 0) + ".bad.com",
      // Invalid quoted string
      "\"user@example.com",
      "user\"@example.com",
      "\"user\\@example.com\"",
      // Invalid escape sequences
      "\"user\\\"@example.com",
      "\"user\\\\\"@example.com",
    ]
  )
  func invalidMailboxParsing(address: String) {
    #expect(EmailAddress.parse(string: address) == nil, "Should reject invalid address: \(address)")
  }

  // MARK: - Properties

  @Test(
    "Mailbox Properties",
    arguments: [
      ("user", "example.com", "user@example.com"),
      ("user.name", "example.com", "user.name@example.com"),
      ("\"user name\"", "example.com", "\"user name\"@example.com"),
      ("user", "[127.0.0.1]", "user@[127.0.0.1]"),
    ]
  )
  func mailboxProperties(local: String, domain: String, expectedString: String) {
    let mailbox = EmailAddress(local: local, domain: domain)
    #expect(mailbox.local == local)
    #expect(mailbox.domain == domain)
    #expect("\(mailbox)" == expectedString)
  }

  // MARK: - Edge Cases

  @Test(
    "Edge Cases",
    arguments: [
      // Empty quoted string
      "\"\"@example.com",
      // Single character
      "a@b.com",
      // Maximum length local part
      "a".padding(toLength: 64, withPad: "a", startingAt: 0) + "@example.com",
      // All special characters
      "!#$%&'*+-/=?^_`{|}~@example.com",
    ]
  )
  func edgeCases(address: String) {
    #expect(EmailAddress.parse(string: address) != nil, "Should handle edge case: \(address)")
  }
}

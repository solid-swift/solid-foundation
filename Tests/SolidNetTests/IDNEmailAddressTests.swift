//
//  IDNEmailAddressTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

@testable import SolidNet
import Testing


@Suite("IDN EmailAddress Tests")
final class IDNEmailAddressTests {

  // MARK: - Initialization

  @Test(
    "Initialize IDN email with components",
    arguments: [
      ("χρήστης", "παράδειγμα.δοκιμή", "χρήστης@παράδειγμα.δοκιμή"),
      ("\\\"ユーザー 名\\\"", "例.テスト", "\\\"ユーザー 名\\\"@例.テスト"),
      ("user", "[2001:db8::1]", "user@[2001:db8::1]"),
    ]
  )
  func initIDNEmail(local: String, domain: String, expected: String) {
    let m = IDNEmailAddress(local: local, domain: domain)
    #expect(m.local == local)
    #expect(m.domain == domain)
    #expect(m.encoded == expected)
  }

  // MARK: - Formatting

  @Test("Encoding and description for simple IDN email")
  func formattingSimpleIDN() {
    let m = IDNEmailAddress(local: "χρήστης", domain: "παράδειγμα.δοκιμή")
    #expect(m.encoded == "χρήστης@παράδειγμα.δοκιμή")
    #expect("\(m)" == "χρήστης@παράδειγμα.δοκιμή")
  }

  @Test("Quoted Unicode local part preserved in formatting")
  func formattingQuotedUnicodeLocal() {
    let m = IDNEmailAddress(local: "\"ユーザー 名\"", domain: "例.テスト")
    #expect(m.encoded == "\"ユーザー 名\"@例.テスト")
    #expect(m.description == "\"ユーザー 名\"@例.テスト")
  }

  @Test("IDN IPv4 domain-literal formatting")
  func formattingIDNIPv4DomainLiteral() {
    let domain = "[192.0.2.10]"
    let m = IDNEmailAddress(local: "ユーザー", domain: domain)
    #expect(m.encoded == "ユーザー@" + domain)
  }

  @Test("IDN IPv6 domain-literal formatting")
  func formattingIDNIPv6DomainLiteral() {
    let domain = "[IPv6:2001:db8::1]"
    let m = IDNEmailAddress(local: "χρήστης", domain: domain)
    #expect(m.description == "χρήστης@" + domain)
  }

  @Test("Parsing preserves formatting on output (IDN)")
  func formattingFromParseIDN() throws {
    let email = "χρήστης@παράδειγμα.δοκιμή"
    let m = try #require(IDNEmailAddress.parse(string: email))
    #expect(m.encoded == email)
    #expect("\(m)" == email)
  }

  // MARK: - Parsing

  @Test(
    "Valid ASCII email addresses",
    arguments: [
      ("user", "example.com", "Basic ASCII email"),
      ("user.name", "example.com", "ASCII email with dot"),
      ("user+tag", "example.com", "ASCII email with plus tag"),
      ("user!name", "example.com", "ASCII email with exclamation"),
      ("user#name", "example.com", "ASCII email with hash"),
      ("user$name", "example.com", "ASCII email with dollar"),
      ("user%name", "example.com", "ASCII email with percent"),
      ("user&name", "example.com", "ASCII email with ampersand"),
      ("user'name", "example.com", "ASCII email with apostrophe"),
      ("user*name", "example.com", "ASCII email with asterisk"),
      ("user+name", "example.com", "ASCII email with plus"),
      ("user/name", "example.com", "ASCII email with slash"),
      ("user=name", "example.com", "ASCII email with equals"),
      ("user?name", "example.com", "ASCII email with question mark"),
      ("user^name", "example.com", "ASCII email with caret"),
      ("user_name", "example.com", "ASCII email with underscore"),
      ("user`name", "example.com", "ASCII email with backtick"),
      ("user{name", "example.com", "ASCII email with opening brace"),
      ("user|name", "example.com", "ASCII email with pipe"),
      ("user}name", "example.com", "ASCII email with closing brace"),
      ("user~name", "example.com", "ASCII email with tilde"),
      ("user-name", "example.com", "ASCII email with hyphen"),
      ("\"user name\"", "example.com", "ASCII email with quoted spaces"),
      ("\"user@name\"", "example.com", "ASCII email with quoted at symbol"),
      ("user", "[127.0.0.1]", "ASCII email with IP address domain"),
    ]
  )
  func validAsciiEmails(local: String, domain: String, description: String) throws {
    let email = "\(local)@\(domain)"
    let mailbox = try #require(IDNEmailAddress.parse(string: email))
    #expect(
      mailbox.local == local,
      "Local part mismatch for \(description): expected '\(local)', got '\(mailbox.local)'"
    )
    #expect(
      mailbox.domain == domain,
      "Domain mismatch for \(description): expected '\(domain)', got '\(mailbox.domain)'"
    )
  }

  @Test(
    "Valid internationalized email addresses",
    arguments: [
      ("用户", "例子.测试", "Chinese email"),
      ("사용자", "예시.테스트", "Korean email"),
      ("ユーザー", "例.テスト", "Japanese email"),
      ("пользователь", "пример.тест", "Russian email"),
      ("χρήστης", "παράδειγμα.δοκιμή", "Greek email"),
      ("مستخدم", "مثال.اختبار", "Arabic email"),
      ("उपयोगकर्ता", "उदाहरण.परीक्षण", "Hindi email"),
      ("user", "xn--fsq.jp", "IDN domain email"),
      ("\"user name with spaces\"", "example.com", "Quoted local part with spaces"),
      ("\"user@name with at\"", "example.com", "Quoted local part with at symbol"),
    ]
  )
  func validInternationalizedEmails(local: String, domain: String, description: String) throws {
    let email = "\(local)@\(domain)"
    let mailbox = try #require(IDNEmailAddress.parse(string: email))
    #expect(
      mailbox.local == local,
      "Local part mismatch for \(description): expected '\(local)', got '\(mailbox.local)'"
    )
    #expect(
      mailbox.domain == domain,
      "Domain mismatch for \(description): expected '\(domain)', got '\(mailbox.domain)'"
    )
  }

  @Test(
    "Invalid email addresses",
    arguments: [
      ("", "Empty string"),
      ("@example.com", "Missing local part"),
      ("user@", "Missing domain"),
      ("user@example", "Invalid domain"),
      ("user@example..com", "Double dot in domain"),
      ("user@.example.com", "Leading dot in domain"),
      ("user@example.com.", "Trailing dot in domain"),
      ("user@-example.com", "Leading hyphen in domain"),
      ("user@example-.com", "Trailing hyphen in domain"),
      ("user name@example.com", "Space in local part without quotes"),
      ("user@name@example.com", "Multiple @ symbols"),
      ("user@example.com@", "Multiple @ symbols"),
      ("user@example.com..", "Multiple trailing dots"),
      ("user@example.com-", "Trailing hyphen"),
      ("user@example.com--", "Multiple trailing hyphens"),
    ]
  )
  func invalidEmails(email: String, description: String) throws {
    #expect(IDNEmailAddress.parse(string: email) == nil, "Incorrectly parsed invalid email: \(email) - \(description)")
  }

  // MARK: - Properties

  @Test(
    "Email address properties",
    arguments: [
      ("user", "example.com", "Basic email properties"),
      ("user.name", "example.com", "Email with dot in local part"),
      ("user+tag", "example.com", "Email with plus tag"),
      ("用户", "例子.测试", "Internationalized email properties"),
      ("사용자", "예시.테스트", "Korean email properties"),
      ("\"user name\"", "example.com", "Quoted local part properties"),
      ("\"user@name\"", "example.com", "Quoted local part with at symbol"),
      ("user", "[127.0.0.1]", "IP address domain properties"),
    ]
  )
  func emailProperties(local: String, domain: String, description: String) throws {
    let email = "\(local)@\(domain)"
    let mailbox = try #require(IDNEmailAddress.parse(string: email))
    #expect(
      mailbox.local == local,
      "Local part mismatch for \(description): expected '\(local)', got '\(mailbox.local)'"
    )
    #expect(
      mailbox.domain == domain,
      "Domain mismatch for \(description): expected '\(domain)', got '\(mailbox.domain)'"
    )
  }

}

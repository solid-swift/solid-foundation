//
//  Mailbox.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

/// A structure representing an SMTP mailbox.
public struct EmailAddress {
  /// Maibox local identifier.
  ///
  /// Local identifiers are before the "@" in a mailbox address and can consist of a dot-string or a quoted-string.
  public var local: String

  /// Mailbox domain.
  ///
  /// The domain is after the "@" in an address and can be a dot-string of labels or a domain-literal.
  public var domain: String

  /// Initializes a Mailbox instance.
  /// - Parameters:
  ///   - local: The local identifier of the mailbox.
  ///   - domain: The domain of the mailbox.
  public init(local: String, domain: String) {
    self.local = local
    self.domain = domain
  }

  /// A string representation of the mailbox.
  public var encoded: String {
    "\(local)@\(domain)"
  }

  private static nonisolated(unsafe) let parseRegex =
    #/^(?<local>(?:[A-Za-z0-9!#$%&'*+\-\/=?^_`{|}~]+(?:\.[A-Za-z0-9!#$%&'*+\-\/=?^_`{|}~]+)*|"(?:[^\x00-\x1F\x7F"\\]|\\["\\])*"))@(?<domain>(?:[A-Za-z0-9-.]+|\[.+\]))$/#

  /// Attempts to parse a mailbox string according to RFC 5321.
  ///
  /// RFC 5321 (and related RFCs) define a mailbox as:
  ///     mailbox = local-part "@" domain
  ///
  /// local-part can be a dot-string or a quoted-string.
  /// For dot-string, we allow one or more "atoms" separated by dots.
  /// Atoms are composed of allowed characters:
  ///     A–Z, a–z, 0–9 and these symbols: ! # $ % & ' * + - / = ? ^ _ ` { | } ~
  ///
  /// For a quoted-string, we allow any printable ASCII (with proper escaping of
  /// double quotes and backslashes).
  ///
  /// The domain is either a dot-string of labels (letters, digits, and hyphens,
  /// not starting or ending with a hyphen) or a domain-literal enclosed in [ and ].
  ///
  /// - Parameter string: The mailbox string to validate and parse.
  /// - Returns: A Mailbox instance if the input is valid; otherwise, nil.
  public static func parse(string: String) -> Self? {

    // The following regex uses named capture groups "local" and "domain".
    guard let match = string.wholeMatch(of: Self.parseRegex) else {
      return nil
    }

    let local = String(match.output.local)
    let domain = String(match.output.domain)

    // Additional validation
    guard validate(local: local) && validate(domain: domain) else {
      return nil
    }

    return Self(local: local, domain: domain)
  }

  /// Validates the local part of a mailbox address.
  ///
  /// - Parameter local: The local part of the mailbox address.
  /// - Returns: true if valid; false otherwise.
  ///
  public static func validate(local: String) -> Bool {

    // Check max length of local part
    guard local.count <= 64 else {
      return false
    }

    // Validate quoted strings
    if isQuotedString(local) {
      guard validate(quotedString: local) else {
        return false
      }
    }

    return true
  }

  private static func isQuotedString(_ string: String) -> Bool {
    string.hasPrefix("\"") && string.hasSuffix("\"")
  }

  private static func validate(quotedString: String) -> Bool {

    let content = quotedString.dropFirst().dropLast()

    // Check for valid escape sequences
    var i = content.startIndex
    while i < content.endIndex {
      if content[i] == "\\" {
        // Must have a character after the backslash
        let nextIndex = content.index(after: i)
        guard nextIndex < content.endIndex else {
          return false
        }

        // Only " and \ can be escaped
        let nextChar = content[nextIndex]
        guard ["\"", "\\"].contains(nextChar) else {
          return false
        }

        // Skip the escaped character
        i = nextIndex
      }
      i = content.index(after: i)
    }

    // Ensure we don't end with a single backslash
    if content.last == "\\" {
      return false
    }

    return true
  }

  /// Validates the domain part of a mailbox address.
  ///
  /// - Parameter domain: The domain part of the mailbox address.
  /// - Returns: true if valid; false otherwise.
  ///
  public static func validate(domain: String) -> Bool {

    // If the domain is a literal, we need to validate the content
    if isDomainLiteral(domain) {
      guard validate(domainLiteral: domain) else {
        return false
      }
    }
    // Otherwise, validate as a hostname
    else {
      guard
        !domain.hasPrefix(".") && !domain.hasSuffix(".")
          && Hostname.parse(string: String(domain)) != nil
      else {
        return false
      }
    }
    return true
  }

  private static func isDomainLiteral(_ string: String) -> Bool {
    string.hasPrefix("[") && string.hasSuffix("]")
  }

  private static func validate(domainLiteral: String) -> Bool {
    let literalContent = String(domainLiteral.dropFirst().dropLast())
    return validateIPv4AddressLiteral(literalContent)
      || validateIPv6AddressLiteral(literalContent) || validateGeneralLiteral(literalContent)
  }

  private static func validateIPv4AddressLiteral(_ string: String) -> Bool {
    IPv4Address.parse(string: string) != nil
  }

  private static let ipv6LiteralPrefix = "IPv6:"

  private static func validateIPv6AddressLiteral(_ string: String) -> Bool {
    string.hasPrefix(Self.ipv6LiteralPrefix)
      && IPv6Address.parse(string: String(string.trimmingPrefix(Self.ipv6LiteralPrefix)))
        != nil
  }

  private static nonisolated(unsafe) let generalLiteralRegex = #/^[\x21-\x5A\x5E-\x7E]+$/#

  private static func validateGeneralLiteral(_ string: String) -> Bool {
    let parts = string.split(separator: ":", maxSplits: 2)
    guard parts.count == 2 else {
      return false
    }
    // Validate the label is a valid hostname
    let standardizedLabel = String(parts[0])
    guard Hostname.parse(string: standardizedLabel) != nil else {
      return false
    }
    // Validate the content
    let content = String(parts[1])
    guard content.wholeMatch(of: Self.generalLiteralRegex) != nil else {
      return false
    }
    return true
  }

}

extension EmailAddress: Equatable {}

extension EmailAddress: Hashable {}

extension EmailAddress: Sendable {}

extension EmailAddress: CustomStringConvertible {

  public var description: String { encoded }

}

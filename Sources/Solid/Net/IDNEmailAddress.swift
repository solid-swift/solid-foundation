//
//  IDNMailbox.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

/// A structure representing an Internationalized (IDN) email address.
public struct IDNEmailAddress {
  /// Local identifier.
  ///
  /// The local identifier is before the "@" in a mailbox address and can consist of a dot-string or a quoted-string.
  public let local: String

  /// Mailbox domain.
  ///
  /// The domain is after the "@" in an address and can be a dot-string of labels or a domain-literal.
  public let domain: String

  /// Initializes a Mailbox instance.
  ///
  /// - Parameters:
  ///  - local: The local identifier of the mailbox.
  ///  - domain: The domain of the mailbox.
  ///
  public init(local: String, domain: String) {
    self.local = local
    self.domain = domain
  }

  /// A string representation of the mailbox.
  public var encoded: String { "\(local)@\(domain)" }

  private static nonisolated(unsafe) let parseRegex =
    #/^(?<local>(?:[\p{L}\p{N}!#$%&'*+/=?^_`{|}~\-]+(?:\.[\p{L}\p{N}!#$%&'*+/=?^_`{|}~\-]+)*|"(?:[^"\\\r\n]|\\.)*"))@(?<domain>(?:[\p{L}\p{N}\-\.]+|\[.+\]))$/#

  /// Parses an IDN‑email address according to the mailbox production in RFC 6531.
  ///
  /// The local‑part is matched as either:
  ///  - A dot‑string composed of one or more allowed characters (Unicode letters/digits and
  ///    the symbols !#$%&'*+/=?^_`{|}~ and hyphen) separated by literal periods.
  ///  - A quoted‑string enclosed in double quotes that permits escaped printable characters.
  ///
  /// The domain is matched as either:
  ///  - A dot‑string domain of labels (each label starts and ends with a Unicode letter or digit,
  ///    with interior hyphens allowed), or
  ///  - A domain literal enclosed in square brackets.
  ///
  /// - Parameter string: The email address string.
  /// - Returns: An `Mailbox` instance if the input is valid; otherwise, `nil`.
  public static func parse(string: String) -> Self? {

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

  /// Validates the local part of an email address.
  ///
  /// - Parameter local: The local part of the email address.
  /// - Returns: `true` if valid; otherwise, `false`.
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

  /// Validates the domain part of an email address.
  ///
  /// - Parameter domain: The domain part of the email address.
  /// - Returns: `true` if valid; otherwise, `false`.
  public static func validate(domain: String) -> Bool {
    // If the domain is a literal, we need to validate the content
    if isDomainLiteral(domain) {
      guard validate(domainLiteral: domain) else {
        return false
      }
    }
    // Otherwise, validate as a hostname
    else {
      // Must contain at least one dot, not end with a dot, and be a valid hostname
      guard
        domain.contains(".") && !domain.hasSuffix("."),
        IDNHostname.parse(string: String(domain)) != nil
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
      && IPv6Address.parse(string: String(string.trimmingPrefix(Self.ipv6LiteralPrefix))) != nil
  }

  private static nonisolated(unsafe) let generalLiteralRegex = #/^[\x21-\x5A\x5E-\x7E]+$/#

  private static func validateGeneralLiteral(_ string: String) -> Bool {
    let parts = string.split(separator: ":", maxSplits: 2)
    guard parts.count == 2 else {
      return false
    }
    // Validate the label is a valid hostname
    let standardizedLabel = String(parts[0])
    guard IDNHostname.parse(string: standardizedLabel) != nil else {
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

extension IDNEmailAddress: Equatable {}

extension IDNEmailAddress: Hashable {}

extension IDNEmailAddress: Sendable {}

extension IDNEmailAddress: CustomStringConvertible {

  public var description: String { encoded }

}

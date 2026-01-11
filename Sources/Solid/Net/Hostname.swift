//
//  Hostname.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

/// A structure representing a validated hostname.
public struct Hostname {

  /// Maximum overall length for a hostname.
  public static let maxLength = 255

  /// The hostname split into its labels.
  public let labels: [String]

  /// The fully qualified hostname string.
  public var encoded: String {
    labels.joined(separator: ".")
  }

  /// Initializes a Hostname instance with the provided labels.
  ///
  /// - Parameter labels: An array of labels that make up the hostname.
  public init(labels: [String]) {
    self.labels = labels
  }

  /// Attempts to parse and validate a hostname string acording to RFC-1123.
  ///
  /// The hostname must be a series of labels separated by dots.
  /// Each label must either be:
  ///   - a standard label: starting and ending with an alphanumeric character, and containing
  ///     only letters, digits, and hyphens (with a maximum length of 63 characters), or
  ///   - a Punycode label: beginning with the case‑insensitive prefix "xn--" and conforming to the
  ///     same LDH rules (with the remainder being 1–59 characters).
  /// An optional trailing dot is allowed.
  ///
  /// - Parameter string: The hostname string to validate.
  /// - Returns: A Hostname instance if valid; otherwise, nil.
  public static func parse(string: String) -> Hostname? {

    guard let labels = extractLabels(string: string, maxLength: maxLength) else {
      return nil
    }

    // Validate each label is either a valid ASCII label or a valid Punycode label
    for label in labels {
      // Check if it's a Punycode label
      if Punycode.isProbablyPunycode(label) {
        guard Punycode.validate(punycodeLabel: label) else {
          return nil
        }
      }
      // Otherwise check if it's a valid ASCII label
      else {
        guard validate(asciiLabel: label) else {
          return nil
        }
      }
    }

    return Hostname(labels: labels.map(String.init))
  }

  /// Labels for the root domain/hostname.
  public static let rootLabels = ["".dropFirst()]

  /// Extracts component labels from a hostname string if it is valid.
  ///
  /// This function splits a hostname into its component labels by:
  /// - Handling the root domain case (single dot)
  /// - Removing any trailing dot (if present)
  /// - Splitting the string on dots
  /// - Validating label lengths
  ///
  /// - Parameters:
  ///   - string: The hostname string to split into labels
  ///   - maxLength: The maximum allowed length of the hostname
  /// - Returns: An array of substrings representing the individual labels if valid,
  ///           otherwise nil
  public static func extractLabels(string: String, maxLength: Int) -> [Substring]? {
    // Handle empty string
    guard !string.isEmpty else {
      return nil
    }

    // Handle root domain case
    if string == "." {
      return rootLabels
    }

    // Remove a trailing dot if present
    let trimmed = string.dropLast(string.hasSuffix(".") ? 1 : 0)

    // Split into labels
    let labels = trimmed.split(separator: ".", omittingEmptySubsequences: false)

    // Check for empty labels (except for root domain which we handled above)
    guard !labels.contains(where: { $0.isEmpty }) else {
      return nil
    }

    // Check the overall length (excluding dots)
    let lengthWithoutDots = labels.reduce(0) { $0 + $1.count }
    guard lengthWithoutDots <= maxLength else {
      return nil
    }

    // Validate each label's length
    for label in labels {
      // Check label length
      guard label.count >= 1 && label.count <= 63 else {
        return nil
      }
    }

    return labels
  }

  /// Validates whether a given label conforms to the ASCII hostname label format.
  ///
  /// A valid ASCII label must:
  /// - Start with an alphanumeric character
  /// - Contain 0-61 additional alphanumeric characters or hyphens
  /// - End with an alphanumeric character
  /// - Have a total length between 1 and 63 characters
  ///
  /// - Parameter asciiLabel: The string to validate as an ASCII hostname label
  /// - Returns: `true` if the label is a valid ASCII hostname label, `false` otherwise
  public static func validate(asciiLabel: Substring) -> Bool {
    // Matches a label that starts and ends with alphanumeric chars, with optional hyphens in between
    let asciiRegex = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/

    return asciiLabel.wholeMatch(of: asciiRegex) != nil
  }
}

extension Hostname: Equatable {}

extension Hostname: Hashable {}

extension Hostname: Sendable {}

extension Hostname: CustomStringConvertible {

  public var description: String { encoded }

}

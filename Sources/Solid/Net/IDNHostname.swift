//
//  Hostname.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

/// A structure representing a validated hostname.
public struct IDNHostname {

  /// Maximum overall length for a hostname.
  public static let maxLength = 255

  /// The hostname split into its labels.
  public let labels: [String]

  /// The fully qualified hostname string.
  public var value: String {
    labels.joined(separator: ".")
  }

  /// Initializes a Hostname instance with the provided labels.
  ///
  /// - Parameter labels: An array of labels that make up the hostname.
  public init(labels: [String]) {
    self.labels = labels
  }

  /// Attempts to parse and validate an IDN hostname string according to RFC-5890 and RFC-5891 punycode.
  ///
  /// The hostname must be a series of labels separated by dots.
  /// Each label must either be:
  ///   - a Unicode label: starting and ending with a Unicode letter or digit, and containing
  ///     only Unicode letters, digits, and hyphens (with a maximum length of 63 characters), or
  ///   - a Punycode label: beginning with the case‑insensitive prefix "xn--" and conforming to the
  ///     same LDH rules (with the remainder being 1–59 characters).
  /// An optional trailing dot is allowed.
  ///
  /// - Parameters:
  ///   - string: The hostname string to validate.
  ///   - allowRoot: Whether to allow the root domain (.) as a valid hostname.
  /// - Returns: A Hostname instance if valid; otherwise, nil.
  public static func parse(string: String, allowRoot: Bool = false) -> IDNHostname? {

    guard let labels = extractLabelsIfValid(string: string, maxLength: maxLength, allowRoot: allowRoot) else {
      return nil
    }

    // Validate each label is either a valid Unicode label or a valid Punycode label
    for label in labels {
      // Check if it's a Punycode label
      if Punycode.isProbablyPunycode(label) {
        guard Punycode.validate(punycodeLabel: label) else {
          return nil
        }
      }
      // Otherwise check if it's a valid Unicode label
      else if !label.isEmpty {
        guard validate(unicodeLabel: label) else {
          return nil
        }
      }
    }

    return IDNHostname(labels: labels.map(String.init))
  }

  private nonisolated(unsafe) static let dotSeparators = /[.\u{3002}\u{FF0E}\u{FF61}]/

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
  ///   - allowRoot: Whether to allow the root domain (.) as a valid hostname
  /// - Returns: An array of substrings representing the individual labels if valid,
  ///           otherwise nil
  private static func extractLabelsIfValid(string: String, maxLength: Int, allowRoot: Bool) -> [Substring]? {
    // Handle empty string
    guard !string.isEmpty else {
      return nil
    }

    // Handle root domain case
    if string.count == 1 && string.wholeMatch(of: dotSeparators) != nil {
      return allowRoot ? [Substring("")] : nil
    }

    let trimmed =
      if let lastIndex = string.indices.last, string[lastIndex...].wholeMatch(of: dotSeparators) != nil {
        string.dropLast()
      } else {
        string.dropLast(0)
      }

    // Split into labels
    let labels = trimmed.split(separator: Self.dotSeparators, omittingEmptySubsequences: false)

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

  /// Validates whether a given label conforms to the Unicode (U-label) format.
  ///
  /// A valid Unicode label must:
  /// - Start with a Unicode letter or digit (not a combining mark)
  /// - Contain 0-61 additional Unicode letters, digits, or hyphens
  /// - End with a Unicode letter or digit
  /// - Have a total length between 1 and 63 characters
  /// - Not contain consecutive hyphens
  /// - Not start or end with a hyphen
  /// - Not contain any characters that are not PVALID according to RFC 5892
  /// - Not contain any characters that are CONTEXTO or CONTEXTJ according to RFC 5892
  /// - Not contain any characters that are DISALLOWED according to RFC 5892
  ///
  /// - Parameter unicodeLabel: The string to validate as a Unicode hostname label
  /// - Returns: `true` if the label is a valid Unicode hostname label, `false` otherwise
  ///
  public static func validate(unicodeLabel: Substring) -> Bool {
    // Empty labels are allowed (e.g. in "example.com." or ".")
    if unicodeLabel.isEmpty {
      return true
    }

    // Check length requirements
    guard unicodeLabel.count <= 63 else {
      return false
    }

    // Check for consecutive hyphens
    guard !unicodeLabel.contains("--") else {
      return false
    }

    // Check that label doesn't start or end with a hyphen
    guard !unicodeLabel.hasPrefix("-") && !unicodeLabel.hasSuffix("-") else {
      return false
    }

    // Check for mixing of Arabic digit types
    guard hasValidArabicDigits(unicodeLabel) else {
      return false
    }

    // Check for combining marks
    guard
      let firstChar = unicodeLabel.first,
      let firstCharScalar = firstChar.unicodeScalars.first
    else {
      return false
    }
    if firstCharScalar.properties.generalCategory == .nonspacingMark
      || firstCharScalar.properties.generalCategory == .spacingMark
      || firstCharScalar.properties.generalCategory == .enclosingMark
    {
      return false
    }

    // Check each character in the label
    let scalars = unicodeLabel.unicodeScalars
    for scalarIndex in scalars.indices {
      // Check for PVALID characters according to RFC 5892
      let scalar = scalars[scalarIndex]
      let category = scalar.properties.generalCategory
      let value = scalar.value

      // Check if character is in a script that commonly uses joining
      let isJoiningScript =
        // Arabic
        (value >= 0x0600 && value <= 0x06FF)
        // Syriac
        || (value >= 0x0700 && value <= 0x074F)
        // Mandaic
        || (value >= 0x0840 && value <= 0x085F)
        // Devanagari
        || (value >= 0x0900 && value <= 0x097F)
        // Manichaean
        || (value >= 0x10AC0 && value <= 0x10AFF)
        // Psalter Pahlavi
        || (value >= 0x10B80 && value <= 0x10BAF)

      let isLetter =
        category == .uppercaseLetter || category == .lowercaseLetter || category == .titlecaseLetter
        || category == .modifierLetter || category == .otherLetter
      let isDigit = category == .decimalNumber
      let isHyphen = scalar == "-"
      let isException = isException(scalar)
      let isMark = category == .nonspacingMark || category == .spacingMark || category == .enclosingMark
      let isSymbol =
        category == .otherSymbol || category == .mathSymbol || category == .currencySymbol
        || category == .modifierSymbol || category == .otherSymbol

      // Check for CONTEXTO or CONTEXTJ characters
      if let isValidContextual = isValidInContext(scalar, in: scalars, at: scalarIndex) {
        // If it's a contextual character, its validity depends only on its context
        guard isValidContextual else {
          return false
        }
        continue
      }

      // For non-contextual characters, check if they're PVALID and not DISALLOWED
      guard
        (isLetter || isDigit || isHyphen || isException || (isJoiningScript && (isMark || isSymbol)))
          && !isDisallowed(scalar)
      else {
        return false
      }
    }

    return true
  }

  /// Checks if a Unicode scalar is one of the exceptions that are PVALID according to RFC 5892.
  ///
  /// These are characters that are not letters or digits but are explicitly allowed by RFC 5892.
  ///
  /// - Parameter scalar: The Unicode scalar to check
  /// - Returns: `true` if the scalar is a PVALID exception, `false` otherwise
  private static func isException(_ scalar: Unicode.Scalar) -> Bool {
    // Exceptions from RFC 5892 Section 2.6
    let exceptions: Set<Unicode.Scalar> = [
      // U+00DF LATIN SMALL LETTER SHARP S
      "\u{00DF}",
      // U+03C2 GREEK SMALL LETTER FINAL SIGMA
      "\u{03C2}",
      // U+0F0B TIBETAN MARK INTERSYLLABIC TSHEG
      "\u{0F0B}",
      // U+3007 IDEOGRAPHIC NUMBER ZERO
      "\u{3007}",
      // U+0640 ARABIC TATWEEL
      "\u{0640}",
      // U+07FA NKO LAJANYALAN
      "\u{07FA}",
    ]
    return exceptions.contains(scalar)
  }

  /// Checks if a Unicode scalar is valid in its context according to RFC 5892.
  ///
  /// This function handles both CONTEXTO and CONTEXTJ characters:
  ///
  /// CONTEXTO characters:
  /// - Middle Dot (U+00B7) - must be preceded and followed by 'l'
  /// - Greek Lower Numeral Sign (U+0375) - must be followed by Greek letters
  /// - Hebrew Punctuation Geresh (U+05F3) - must be preceded by Hebrew letters
  /// - Hebrew Punctuation Gershayim (U+05F4) - must be preceded by Hebrew letters
  /// - KATAKANA MIDDLE DOT (U+30FB) - must be preceded and followed by KATAKANA or HIRAGANA
  /// - KATAKANA-HIRAGANA VOICED SOUND MARK (U+309B) - must be preceded by KATAKANA or HIRAGANA
  /// - KATAKANA-HIRAGANA SEMI-VOICED SOUND MARK (U+309C) - must be preceded by KATAKANA or HIRAGANA
  ///
  /// CONTEXTJ characters:
  /// - Zero Width Joiner (U+200D) - must be preceded and followed by characters that can join
  /// - Zero Width Non-Joiner (U+200C) - must be preceded and followed by characters that can join
  ///
  /// - Parameters:
  ///   - scalar: The Unicode scalar to check
  ///   - scalars: The Unicode scalars of  the entire label
  ///   - index: The index of the scalar in the label
  /// - Returns: `nil` if the scalar is not a CONTEXTO or CONTEXTJ character, `true` if it is and its context is valid, `false` if it is and its context is invalid
  private static func isValidInContext(
    _ scalar: Unicode.Scalar,
    in scalars: Substring.UnicodeScalarView,
    at index: Substring.UnicodeScalarView.Index
  ) -> Bool? {
    // Get the previous and next scalars
    let prevScalar = scalars.index(index, offsetBy: -1, limitedBy: scalars.startIndex).map { scalars[$0] }
    let nextScalar = scalars.index(index, offsetBy: 1, limitedBy: scalars.index(before: scalars.endIndex))
      .map { scalars[$0] }

    // Check for CONTEXTO characters
    switch scalar {
    case "\u{00B7}":    // MIDDLE DOT
      // Must be preceded and followed by 'l'
      return prevScalar?.value == 0x6C && nextScalar?.value == 0x6C    // 'l' is U+006C
    case "\u{0375}":    // GREEK LOWER NUMERAL SIGN
      // Must be followed by Greek letters
      guard let nextScalar else { return false }
      // Check if the character is a Greek letter (uppercase or lowercase)
      return (nextScalar.value >= 0x0391 && nextScalar.value <= 0x03A9)    // Uppercase Greek
        || (nextScalar.value >= 0x03B1 && nextScalar.value <= 0x03C9)    // Lowercase Greek
    case "\u{05F3}", "\u{05F4}":    // HEBREW PUNCTUATION GERESH/GERSHAYIM
      // Must be preceded by Hebrew letters
      guard let prevScalar else { return false }
      // Check if the character is in the Hebrew script range and is a letter
      return (prevScalar.value >= 0x0590 && prevScalar.value <= 0x05FF)
        && prevScalar.properties.generalCategory == .otherLetter
    case "\u{30FB}":    // KATAKANA MIDDLE DOT
      // Must have at least one character in the label that is Hiragana, Katakana, or Han
      return scalars.enumerated()
        .contains { (charIndex, scalar) in
          // Skip the current character
          guard scalars.index(scalars.startIndex, offsetBy: charIndex) != index else { return false }
          // Check if any character is in Hiragana (3040-309F), Katakana (30A0-30FF), or Han (4E00-9FFF) ranges
          let value = scalar.value
          return (value >= 0x3040 && value <= 0x309F)    // Hiragana
            || (value >= 0x30A0 && value <= 0x30FF)    // Katakana
            || (value >= 0x4E00 && value <= 0x9FFF)    // Han (Basic)
        }
    case "\u{309B}", "\u{309C}":    // KATAKANA-HIRAGANA VOICED/SEMI-VOICED SOUND MARK
      // Must be preceded by KATAKANA or HIRAGANA
      guard let prevScalar else { return false }
      // Check if the character is in the KATAKANA or HIRAGANA range
      return (prevScalar.value >= 0x30A0 && prevScalar.value <= 0x30FF)    // KATAKANA
        || (prevScalar.value >= 0x3040 && prevScalar.value <= 0x309F)    // HIRAGANA
    case "\u{200D}":    // ZERO WIDTH JOINER
      // Must be preceded by Virama
      guard let prevScalar else { return false }
      return prevScalar.properties.canonicalCombiningClass.rawValue == 9    // Virama = 9
    case "\u{200C}":    // ZERO WIDTH NON-JOINER
      // Must be preceded by Virama OR be in a cursive script context
      guard let prevScalar else { return false }
      if prevScalar.properties.canonicalCombiningClass.rawValue == 9 {    // Virama = 9
        return true
      }
      // Check for cursive script context according to RFC 5892
      return isValidZWNJContext(scalars, at: index)
    default:
      return nil
    }
  }

  /// Checks if a Unicode scalar is DISALLOWED according to RFC 5892.
  ///
  /// DISALLOWED characters include:
  /// - Control characters (C0 and C1)
  /// - Format characters
  /// - Private Use characters
  /// - Surrogate characters
  /// - Characters with the Deprecated property
  /// - Characters with the Variation_Selector property
  /// - Characters with the Soft_Dotted property
  ///
  /// - Parameter scalar: The Unicode scalar to check
  /// - Returns: `true` if the scalar is DISALLOWED, `false` otherwise
  private static func isDisallowed(_ scalar: Unicode.Scalar) -> Bool {
    let category = scalar.properties.generalCategory
    let value = scalar.value

    // Basic DISALLOWED categories
    if category == .control || category == .format || category == .privateUse || category == .surrogate {
      return true
    }

    // Check for Deprecated
    if scalar.properties.isDeprecated {
      return true
    }

    // Check for Variation_Selector
    if scalar.properties.isVariationSelector {
      return true
    }

    // Check for non-characters (U+FDD0..U+FDEF, and others ending in FFFE or FFFF)
    if (value >= 0xFDD0 && value <= 0xFDEF) || (value & 0xFFFE) == 0xFFFE {
      return true
    }

    // Check for specific DISALLOWED characters from RFC 5892
    let disallowedChars: Set<Unicode.Scalar> = [
      // U+0640 ARABIC TATWEEL
      "\u{0640}",
      // U+07FA NKO LAJANYALAN
      "\u{07FA}",
      // U+302E HANGUL SINGLE DOT TONE MARK
      "\u{302E}",
      // U+302F HANGUL DOUBLE DOT TONE MARK
      "\u{302F}",
      // U+3031 VERTICAL KANA REPEAT MARK
      "\u{3031}",
      // U+3032 VERTICAL KANA REPEAT WITH VOICED SOUND MARK
      "\u{3032}",
      // U+3033 VERTICAL KANA REPEAT MARK UPPER HALF
      "\u{3033}",
      // U+3034 VERTICAL KANA REPEAT WITH VOICED SOUND MARK UPPER HALF
      "\u{3034}",
      // U+3035 VERTICAL KANA REPEAT MARK LOWER HALF
      "\u{3035}",
      // U+303B VERTICAL IDEOGRAPHIC ITERATION MARK
      "\u{303B}",
    ]

    return disallowedChars.contains(scalar)
  }

  /// Checks if a label contains valid Arabic digits.
  ///
  /// A label is considered valid if it contains only Arabic-Indic digits or
  /// extended Arabic-Indic digits, but not both.
  ///
  /// - Parameter label: The label to check
  /// - Returns: `true` if the label contains valid Arabic digits, `false` otherwise
  ///
  private static func hasValidArabicDigits(_ label: Substring) -> Bool {
    var foundArabicIndic = false
    var foundExtendedArabicIndic = false

    for scalar in label.unicodeScalars {
      let value = scalar.value

      if value >= 0x0660 && value <= 0x0669 {
        foundArabicIndic = true
      }
      if value >= 0x06F0 && value <= 0x06F9 {
        foundExtendedArabicIndic = true
      }
      // If we found both types, fail immediately
      if foundArabicIndic && foundExtendedArabicIndic {
        return false
      }
    }

    return true
  }

  private static func getJoiningType(_ scalar: Unicode.Scalar) -> JoiningType {
    let value = scalar.value

    // Arabic Letters
    if (value >= 0x0620 && value <= 0x064A)    // Basic Arabic
      || (value >= 0x066E && value <= 0x066F)    // Arabic letterlike
      || (value >= 0x0671 && value <= 0x06D3)
    {    // Extended Arabic
      return .dual
    }

    // Specific Dual-joining characters
    if [
      0x0626, 0x0628, 0x062A, 0x062B, 0x062C, 0x062D, 0x062E, 0x0633, 0x0634, 0x0635, 0x0636, 0x0637, 0x0638, 0x0639,
      0x063A, 0x0641, 0x0642, 0x0643, 0x0644, 0x0645, 0x0646, 0x0647, 0x0649, 0x064A,
    ]
    .contains(value) {
      return .dual
    }

    // Right-joining characters
    if [0x0622, 0x0623, 0x0625, 0x0627].contains(value) {
      return .right
    }

    // Left-joining characters
    if [0x0621, 0x0624, 0x0648, 0x0629].contains(value) {
      return .left
    }

    // Transparent characters (marks, etc.)
    if scalar.properties.generalCategory == .nonspacingMark || scalar.properties.generalCategory == .spacingMark
      || scalar.properties.generalCategory == .enclosingMark
    {
      return .transparent
    }

    return .none
  }

  private enum JoiningType {
    case none    // No joining behavior
    case right    // Right-joining (connects to character on the right)
    case left    // Left-joining (connects to character on the left)
    case dual    // Dual-joining (connects to characters on both sides)
    case transparent    // Transparent (doesn't affect joining behavior)
  }

  private static func isValidZWNJContext(
    _ scalars: Substring.UnicodeScalarView,
    at index: Substring.UnicodeScalarView.Index
  ) -> Bool {
    // Find the first non-transparent character before ZWNJ
    var beforeIndex = index
    var foundBefore = false
    while beforeIndex > scalars.startIndex {
      beforeIndex = scalars.index(before: beforeIndex)
      let joiningType = getJoiningType(scalars[beforeIndex])
      if joiningType != .transparent {
        foundBefore = joiningType == .left || joiningType == .dual
        break
      }
    }

    // Find the first non-transparent character after ZWNJ
    var afterIndex = index
    var foundAfter = false
    while afterIndex < scalars.index(before: scalars.endIndex) {
      afterIndex = scalars.index(after: afterIndex)
      let joiningType = getJoiningType(scalars[afterIndex])
      if joiningType != .transparent {
        foundAfter = joiningType == .right || joiningType == .dual
        break
      }
    }

    return foundBefore && foundAfter
  }
}

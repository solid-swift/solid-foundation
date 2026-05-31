//
//  MediaType.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/28/26.
//

/// An Internet media type, also known as a MIME type.
///
/// `MediaType` represents values such as `application/json`, `text/html;charset=utf-8`, or
/// `application/problem+json`. It models general media type syntax and compatibility, not HTTP
/// `Accept` negotiation.
public struct MediaType {

  /// An error that can occur while parsing a media type.
  public enum Error: Swift.Error, Equatable, Sendable {
    /// The source string is not a valid media type.
    case invalid(String)
  }

  /// A top-level media type.
  public struct Kind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {

    /// The serialized top-level type token.
    public let rawValue: String

    /// Creates a top-level media type from a serialized token.
    public init?(rawValue: String) {
      let rawValue = rawValue.lowercased()
      guard MediaTypeTokens.isToken(rawValue) else {
        return nil
      }
      self.rawValue = rawValue
    }

    /// Creates a top-level media type from a string literal.
    public init(stringLiteral value: String) {
      guard let type = Self(rawValue: value) else {
        fatalError("Invalid type for media type: \(value)")
      }
      self = type
    }

    public static let application: Self = "application"
    public static let audio: Self = "audio"
    public static let example: Self = "example"
    public static let font: Self = "font"
    public static let image: Self = "image"
    public static let message: Self = "message"
    public static let model: Self = "model"
    public static let multipart: Self = "multipart"
    public static let text: Self = "text"
    public static let video: Self = "video"
    public static let any: Self = "*"
  }

  /// A registration tree prefix for a media subtype.
  public struct Tree: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {

    /// The serialized registration tree prefix.
    public let rawValue: String

    /// Creates a registration tree prefix.
    public init?(rawValue: String) {
      let rawValue = rawValue.lowercased()
      guard rawValue.isEmpty || rawValue == "x-" || Self.isFacet(rawValue) else {
        return nil
      }
      self.rawValue = rawValue
    }

    /// Creates a registration tree prefix from a string literal.
    public init(stringLiteral value: String) {
      guard let subtype = Self(rawValue: value) else {
        fatalError("Invalid tree for media type: \(value)")
      }
      self = subtype
    }

    public static let standard: Self = ""
    public static let vendor: Self = "vnd."
    public static let personal: Self = "prs."
    public static let unregistered: Self = "x."
    public static let obsolete: Self = "x-"

    private static func isFacet(_ value: String) -> Bool {
      guard value.hasSuffix(".") else {
        return false
      }

      let facet = String(value.dropLast())
      return !facet.isEmpty &&
        !facet.contains(".") &&
        !facet.contains("+") &&
        facet != "*" &&
        MediaTypeTokens.isToken(facet)
    }
  }

  /// A structured syntax suffix for a media subtype.
  public struct Suffix: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {

    /// The serialized suffix token, without the leading `+`.
    public let rawValue: String

    /// Creates a structured syntax suffix.
    public init?(rawValue: String) {
      let rawValue = rawValue.lowercased()
      guard MediaTypeTokens.isToken(rawValue), !rawValue.contains("+") else {
        return nil
      }
      self.rawValue = rawValue
    }

    /// Creates a structured syntax suffix from a string literal.
    public init(stringLiteral value: String) {
      guard let suffix = Self(rawValue: value) else {
        fatalError("Invalid suffix for media type: \(value)")
      }
      self = suffix
    }

    /// The `+json` structured syntax suffix.
    public static let json: Self = "json"
    /// The `+xml` structured syntax suffix.
    public static let xml: Self = "xml"
    /// The `+cbor` structured syntax suffix.
    public static let cbor: Self = "cbor"
    /// The `+cbor-seq` structured syntax suffix.
    public static let cborSequence: Self = "cbor-seq"
  }

  /// The standard `charset` media type parameter name.
  public static let charsetParameter = "charset"

  /// The top-level media type.
  public let type: Kind

  /// The media subtype registration tree.
  public let tree: Tree

  /// The media subtype without its registration tree or structured suffix.
  public let subtype: String

  /// The structured syntax suffix, without the leading `+`.
  public let suffix: Suffix?

  /// The media type parameters.
  public let parameters: [String: String]

  /// Creates a media type from already separated components.
  ///
  /// Component and parameter names are canonicalized to lowercase.
  public init(
    type: Kind,
    tree: Tree = .standard,
    subtype: String = "*",
    suffix: Suffix? = nil,
    parameters: [String: String] = [:]
  ) {
    let subtype = subtype.lowercased()
    precondition(subtype == "*" || MediaTypeTokens.isToken(subtype), "Media subtype must be a token or wildcard")
    precondition(tree == .standard || subtype != "*", "Wildcard subtypes cannot use a registration tree")
    precondition(type != .any || (tree == .standard && subtype == "*"), "Wildcard types require a wildcard subtype")
    precondition(
      tree != .standard || (!subtype.contains(".") && !subtype.hasPrefix(Tree.obsolete.rawValue)),
      "Faceted subtypes must use a registration tree"
    )
    precondition(
      parameters.keys.allSatisfy { name in
        MediaTypeTokens.isToken(name) && name.lowercased() != "q"
      },
      "Media type parameter names must be tokens and cannot be q"
    )
    precondition(
      parameters.values.allSatisfy(MediaTypeTokens.canSerializeParameterValue),
      "Media type parameter values must be serializable as tokens or quoted strings"
    )

    self.type = type
    self.tree = tree
    self.subtype = subtype
    self.suffix = suffix
    self.parameters = Dictionary(
      uniqueKeysWithValues: parameters.map { key, value in
        let name = key.lowercased()
        return (name, Self.normalizeParameterValue(value, for: name))
      }
    )
  }

  /// Parses a media type from a serialized string.
  public init?(_ string: String) {
    guard let mediaType = try? Self.parse(string) else {
      return nil
    }
    self = mediaType
  }

  /// Parses a media type from a serialized string.
  public init?(string: String) {
    self.init(string)
  }

  /// Parses a media type from a serialized string or throws when it is invalid.
  public static func parse(_ string: String) throws -> MediaType {
    try MediaTypeParser(string).parse()
  }

  /// Returns the value of a named parameter.
  public func parameter(_ name: String) -> String? {
    parameters[name.lowercased()]
  }

  /// Returns a copy with a parameter set to the provided value.
  public func with(parameter name: String, value: String) -> MediaType {
    let name = name.lowercased()
    var parameters = self.parameters
    parameters[name] = Self.normalizeParameterValue(value, for: name)
    return MediaType(type: type, tree: tree, subtype: subtype, suffix: suffix, parameters: parameters)
  }

  /// Returns the canonical serialized form.
  public var serialized: String {
    let suffix = suffix.map { "+\($0.rawValue)" } ?? ""
    let serializedParameters = parameters.keys.sorted().map { key in
      ";\(key)=\(Self.serializeParameterValue(parameters[key]!))"
    }.joined()
    return "\(type.rawValue)/\(tree.rawValue)\(subtype)\(suffix)\(serializedParameters)"
  }

  /// Returns true when the two media types are compatible.
  public func matches(_ other: MediaType) -> Bool {
    if type != .any, other.type != .any, type != other.type {
      return false
    }
    if subtype != "*", other.subtype != "*", tree != other.tree {
      return false
    }
    if subtype != "*", other.subtype != "*", subtype != other.subtype {
      return false
    }
    switch (suffix, other.suffix) {
    case let (suffix?, otherSuffix?):
      if suffix != otherSuffix {
        return false
      }
    case (.some, nil):
      if other.subtype != "*" {
        return false
      }
    case (nil, .some):
      if subtype != "*" {
        return false
      }
    case (nil, nil):
      break
    }
    for (key, value) in parameters {
      if let otherValue = other.parameters[key], value != otherValue {
        return false
      }
    }
    return true
  }

  private static func normalizeParameterValue(_ value: String, for name: String) -> String {
    if name == charsetParameter {
      return value.lowercased()
    }
    return value
  }

  static func parseParameterValue(_ value: String) -> String? {
    MediaTypeTokens.parseParameterValue(value)
  }

  static func serializeParameterValue(_ value: String) -> String {
    MediaTypeTokens.serializeParameterValue(value)
  }

  static func isToken(_ value: String) -> Bool {
    MediaTypeTokens.isToken(value)
  }
}

extension MediaType: Codable {

  /// Decodes a media type from its serialized string form.
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    guard let mediaType = Self(value) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid media type: \(value)")
    }
    self = mediaType
  }

  /// Encodes the media type as its serialized string form.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(serialized)
  }
}

extension MediaType.Kind: Codable {

  /// Decodes a top-level media type from a serialized token.
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    guard let kind = Self(rawValue: value) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid media type kind")
    }
    self = kind
  }

  /// Encodes the top-level media type as a serialized token.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

extension MediaType.Tree: Codable {

  /// Decodes a media subtype tree from a serialized prefix.
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    guard let tree = Self(rawValue: value) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid media type tree")
    }
    self = tree
  }

  /// Encodes the media subtype tree as a serialized prefix.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

extension MediaType.Suffix: Codable {

  /// Decodes a structured syntax suffix from a serialized token.
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    guard let suffix = Self(rawValue: value) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid media type suffix")
    }
    self = suffix
  }

  /// Encodes the structured syntax suffix as a serialized token.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

extension MediaType: Equatable {}

extension MediaType: Hashable {}

extension MediaType: Sendable {}

extension MediaType: CustomStringConvertible {

  /// The canonical serialized form of this media type.
  public var description: String { serialized }
}

extension MediaType: LosslessStringConvertible {}

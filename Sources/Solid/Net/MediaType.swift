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
  public enum Kind: String, CaseIterable, Codable, Hashable, Sendable {
    case application
    case audio
    case example
    case font
    case image
    case message
    case model
    case multipart
    case text
    case video
    case any = "*"
  }

  /// A registration tree prefix for a media subtype.
  public enum Tree: String, CaseIterable, Codable, Hashable, Sendable {
    case standard = ""
    case vendor = "vnd."
    case personal = "prs."
    case unregistered = "x."
    case obsolete = "x-"
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
  public let suffix: String?

  /// The media type parameters.
  public let parameters: [String: String]

  /// Creates a media type from already separated components.
  ///
  /// Component and parameter names are canonicalized to lowercase.
  public init(
    type: Kind,
    tree: Tree = .standard,
    subtype: String = "*",
    suffix: String? = nil,
    parameters: [String: String] = [:]
  ) {
    self.type = type
    self.tree = tree
    self.subtype = subtype.lowercased()
    self.suffix = suffix?.lowercased()
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
    let suffix = suffix.map { "+\($0)" } ?? ""
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
    return Set(parameters.keys).intersection(other.parameters.keys)
      .allSatisfy { parameters[$0] == other.parameters[$0] }
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
    self = try Self.parse(value)
  }

  /// Encodes the media type as its serialized string form.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(serialized)
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

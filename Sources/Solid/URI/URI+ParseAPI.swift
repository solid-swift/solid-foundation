//
//  URI+ParseAPI.swift
//  SolidFoundation
//
//  Adds unified parsing API and diagnostics to URI, aligning with URI.Template.
//

import Foundation

extension URI {

  // MARK: Unified Parsing API (aligned with URI.Template)

  public struct ParseOptions: Sendable, Hashable {
    public var requirements: Set<Requirement>
    public init(requirements: Set<Requirement> = .uriReference) {
      self.requirements = requirements
    }
  }

  public struct ParseError: Error, Sendable, Hashable, CustomStringConvertible {
    public enum Code: String, Sendable {
      case invalidInput
      case invalidScheme
      case invalidAuthority
      case invalidUserInfo
      case invalidHost
      case invalidIPv6
      case invalidPort
      case invalidPath
      case invalidQuery
      case invalidFragment
      case badPercentTriplet
      case requirementViolation
    }
    public let code: Code
    public let offset: Int?
    public let message: String
    public var description: String { "\(code): \(message)\(offset.map { " @\($0)" } ?? "")" }
    public init(code: Code, offset: Int? = nil, message: String) {
      self.code = code
      self.offset = offset
      self.message = message
    }
  }

  public struct ParseDiagnostic: Sendable, Hashable {
    public enum Level: Sendable { case error, warning, note }
    public let level: Level
    public let offset: Int?
    public let message: String
    public init(level: Level, offset: Int? = nil, message: String) {
      self.level = level
      self.offset = offset
      self.message = message
    }
  }

  public struct ParseResult: Sendable {
    public let value: URI?
    public let diagnostics: [ParseDiagnostic]
  }

  /// Strict throwing parse with diagnostics.
  public init(parsing string: String, options: ParseOptions = .init()) throws {
    var p = Parser(string: string, requirements: options.requirements)
    guard let u = p.parse() else {
      if let e = p.error { throw ParseError(code: Self.mapCode(e.code), offset: e.offset, message: e.message) }
      throw ParseError(code: .invalidInput, message: "Invalid URI: does not satisfy requirements")
    }
    self = u
  }

  /// Non-throwing parse with diagnostics.
  public static func parse(_ string: String, options: ParseOptions = .init()) -> ParseResult {
    var p = Parser(string: string, requirements: options.requirements)
    if let u = p.parse() {
      return ParseResult(value: u, diagnostics: [])
    }
    if let e = p.error {
      return ParseResult(
        value: nil,
        diagnostics: [ParseDiagnostic(level: .error, offset: e.offset, message: e.message)]
      )
    }
    return ParseResult(
      value: nil,
      diagnostics: [ParseDiagnostic(level: .error, message: "Invalid URI: does not satisfy requirements")]
    )
  }

  /// Failable initializer: nil on parse failure.
  public init?(encoded string: String, options: ParseOptions) {
    guard let u = URI.parse(string: string, requirements: options.requirements) else { return nil }
    self = u
  }

  /// Known-valid initializer: crashes on parse failure.
  public init(valid string: String, options: ParseOptions) {
    guard let u = URI.parse(string: string, requirements: options.requirements) else {
      fatalError("Invalid URI: \(string)")
    }
    self = u
  }

  /// Convenience to mirror `valid(_:)` with options.
  public static func valid(_ string: String, options: ParseOptions) -> URI {
    URI(valid: string, options: options)
  }
  private static func mapCode(_ c: URI.Parser.ParserError.Code) -> ParseError.Code {
    switch c {
    case .invalidScheme: return .invalidScheme
    case .invalidAuthority: return .invalidAuthority
    case .invalidUserInfo: return .invalidUserInfo
    case .invalidHost: return .invalidHost
    case .invalidIPv6: return .invalidIPv6
    case .invalidPort: return .invalidPort
    case .invalidPath: return .invalidPath
    case .invalidQuery: return .invalidQuery
    case .invalidFragment: return .invalidFragment
    case .badPercentTriplet: return .badPercentTriplet
    case .requirementViolation: return .requirementViolation
    }
  }
}

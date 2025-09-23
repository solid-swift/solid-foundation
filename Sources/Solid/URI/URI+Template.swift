//
//  URITemplate.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation

extension URI {

  /// RFC 6570 URI Template.
  ///
  /// A template is a string with expressions that can be expanded into a URI reference
  /// by substituting variables. Templates are not URIs; use `expandURI` to obtain a URI.
  ///
  public struct Template: Sendable, Hashable, ExpressibleByStringLiteral {

    // MARK: Parsing API (aligned with URI)

    public struct ParseOptions: Sendable, Hashable {

      public enum ExpressionErrorPolicy: Sendable {
        case error
        case copyUnexpanded
      }

      public var expressionErrorPolicy: ExpressionErrorPolicy = .error

      public init(expressionErrorPolicy: ExpressionErrorPolicy = .error) {
        self.expressionErrorPolicy = expressionErrorPolicy
      }
    }

    public struct ParseError: Swift.Error, Sendable, Hashable, CustomStringConvertible {
      public enum Code: String, Sendable {
        case unterminatedExpression
        case emptyExpression
        case invalidOperator
        case invalidVarname
        case invalidModifier
        case invalidPrefixLength
        case malformedTemplate
      }
      public let code: Code
      public let offset: Int?
      public let message: String
      public var description: String { "\(code): \(message)\(offset.map { " @\($0)" } ?? "")" }
      public init(code: Code, offset: Int?, message: String) {
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
      public init(level: Level, offset: Int?, message: String) {
        self.level = level
        self.offset = offset
        self.message = message
      }
    }

    public struct ParseResult: Sendable {
      public let value: URI.Template?
      public let diagnostics: [ParseDiagnostic]
    }

    public enum Error: Swift.Error, Sendable, Equatable, CustomStringConvertible {
      case malformedTemplate(String, offset: Int?)
      case malformedExpression(String, offset: Int?)
      case emptyExpression(offset: Int?)
      case invalidModifier(offset: Int?)
      case invalidPrefixLength(offset: Int?)
      case invalidVarname(offset: Int?)
      case expansionFailed(String)
      case valueTypeMismatch(String)

      public var description: String {
        switch self {
        case .malformedTemplate(let s, _): return "Malformed template: \(s)"
        case .malformedExpression(let s, _): return "Malformed expression: \(s)"
        case .emptyExpression: return "Empty expression"
        case .invalidModifier: return "Invalid modifier"
        case .invalidPrefixLength: return "Invalid prefix length"
        case .invalidVarname: return "Invalid variable name"
        case .expansionFailed(let s): return "Expansion failed: \(s)"
        case .valueTypeMismatch(let s): return "Value type mismatch: \(s)"
        }
      }
    }

    public enum Value: Sendable, Hashable {
      case scalar(String)
      case list([String])
      case assoc([String: String?])

      var isDefined: Bool {
        switch self {
        case .scalar: return true    // empty string is defined
        case .list(let arr): return !arr.isEmpty
        case .assoc(let dict):
          return dict.contains { _, v in v != nil }
        }
      }
    }

    public struct Expression: Sendable, Hashable {
      public enum Operator: Character, Sendable, Hashable {
        case none = "\0"
        case plus = "+"
        case hash = "#"
        case dot = "."
        case slash = "/"
        case semicolon = ";"
        case query = "?"
        case amp = "&"
      }

      public struct VarSpec: Sendable, Hashable {
        public let name: String
        public let explode: Bool
        public let prefixLength: Int?
      }

      public let op: Operator
      public let vars: [VarSpec]
    }

    public enum Part: Sendable, Hashable {
      case literal(String)
      case expression(Expression)
    }

    public let raw: String
    public let parts: [Part]
    public let variables: Set<String>
    public let level: Int

    ///
    public let parsedSuccessfully: Bool

    /// Creates a new template by strictly parsing a raw RFC 6570 template string.
    ///
    /// Parsing is strict and fails if any expression is malformed (invalid operator,
    /// varname, or modifier) according to RFC 6570 Level 1–4 grammar.
    ///
    /// - Parameter raw: The raw RFC 6570 template string to parse.
    /// - Throws: ``URI/Template/ParseError`` when the template is malformed.
    /// - SeeAlso: ``init(parsing:options:)``, ``parse(_:options:)``, ``init(raw:options:)``
    ///
    public init(_ raw: String) throws {
      self.raw = raw
      self.parts = try Self.parseParts(raw)
      self.variables = Set(
        parts.flatMap { part -> [String] in
          guard case .expression(let e) = part else { return [] }
          return e.vars.map(\.name)
        }
      )
      self.level = Self.computeLevel(parts: parts)
      self.parsedSuccessfully = true
    }

    /// Creates a template from a string literal.
    ///
    /// This initializer cannot throw; if parsing fails, the entire literal is treated
    /// as a single literal-only template (no expressions). To detect whether
    /// expressions were parsed, check ``parsedSuccessfully``.
    ///
    /// For strict validation, prefer ``init(parsing:options:)``,
    /// ``parse(_:options:)``, or ``init(raw:options:)``.
    ///
    /// - Parameter value: A string literal containing a template.
    ///
    public init(stringLiteral value: StringLiteralType) {
      if let parsed = try? Self(value) {
        self = parsed
      } else {
        self = Self(unsafeLiteral: value)
      }
    }

    // Internal fallback initializer that accepts any string as a literal-only template
    init(unsafeLiteral value: String) {
      self.init(fromRaw: value, parts: [.literal(value)], parsedSuccessfully: false)
    }

    // Internal designated initializer from parsed parts
    init(fromRaw raw: String, parts: [Part], parsedSuccessfully: Bool) {
      self.raw = raw
      self.parts = parts
      self.variables = Set(
        parts.flatMap { part -> [String] in
          guard case .expression(let e) = part else { return [] }
          return e.vars.map(\.name)
        }
      )
      self.level = Self.computeLevel(parts: parts)
      self.parsedSuccessfully = parsedSuccessfully
    }

    // MARK: - Public construction aligned with URI

    /// Strictly parses a raw RFC 6570 template string with options.
    ///
    /// This initializer performs a strict parse and throws a ``URI/Template/ParseError``
    /// containing a code and character offset when malformed expressions are found.
    ///
    /// - Parameters:
    ///   - raw: The raw RFC 6570 template string.
    ///   - options: Parse options. Use ``URI/Template/ParseOptions`` to configure behavior
    ///     such as ``URI/Template/ParseOptions/ExpressionErrorPolicy``.
    /// - Throws: ``URI/Template/ParseError`` when the template is malformed.
    /// - SeeAlso: ``parse(_:options:)``, ``init(raw:options:)``
    ///
    public init(parsing raw: String, options: ParseOptions = .init()) throws {
      do {
        let parts = try Self.parseParts(raw, options: options)
        self.init(fromRaw: raw, parts: parts, parsedSuccessfully: true)
      } catch let e as URI.Template.Error {
        throw Self.mapToParseError(e, in: raw)
      } catch {
        throw ParseError(code: .malformedTemplate, offset: nil, message: String(describing: error))
      }
    }

    /// Parses a template without throwing and returns diagnostics.
    ///
    /// Use this for editor/tooling scenarios where you want to collect errors
    /// without throwing. On success, the result contains a value and empty diagnostics.
    /// On failure, the result has a nil value and at least one error diagnostic that
    /// includes a character offset and message.
    ///
    /// - Parameters:
    ///   - raw: The raw RFC 6570 template string.
    ///   - options: Parse options. See ``URI/Template/ParseOptions``.
    /// - Returns: A ``URI/Template/ParseResult`` with the value (if any) and diagnostics.
    /// - SeeAlso: ``init(parsing:options:)``, ``init(raw:options:)``
    ///
    public static func parse(_ raw: String, options: ParseOptions = .init()) -> ParseResult {
      do {
        let parts = try Self.parseParts(raw, options: options)
        let value = URI.Template(fromRaw: raw, parts: parts, parsedSuccessfully: true)
        return ParseResult(value: value, diagnostics: [])
      } catch let e as URI.Template.Error {
        let pe = mapToParseError(e, in: raw)
        return ParseResult(
          value: nil,
          diagnostics: [ParseDiagnostic(level: .error, offset: pe.offset, message: pe.description)]
        )
      } catch {
        return ParseResult(
          value: nil,
          diagnostics: [ParseDiagnostic(level: .error, offset: nil, message: String(describing: error))]
        )
      }
    }

    /// Creates a template by parsing a raw string and returning `nil` on failure.
    ///
    /// - Parameters:
    ///   - raw: The raw RFC 6570 template string.
    ///   - options: Parse options. See ``URI/Template/ParseOptions``.
    /// - SeeAlso: ``init(parsing:options:)``, ``parse(_:options:)``
    ///
    public init?(raw: String, options: ParseOptions = .init()) {
      guard case .some(let r) = try? URI.Template(parsing: raw, options: options) else { return nil }
      self = r
    }

    /// Creates a template from a string that is known to be valid.
    ///
    /// This initializer will crash if the provided string is not a valid
    /// RFC 6570 template.
    ///
    /// - Parameters:
    ///   - raw: A template string that is known to be valid.
    ///   - options: Parse options. See ``URI/Template/ParseOptions``.
    /// - SeeAlso: ``valid(_:options:)``
    public init(valid raw: String, options: ParseOptions = .init()) {
      guard let v = try? URI.Template(parsing: raw, options: options) else {
        fatalError("Invalid URI Template: \(raw)")
      }
      self = v
    }

    /// Returns a template created from a string that is known to be valid.
    ///
    /// This function will crash if the provided string is not a valid
    /// RFC 6570 template.
    ///
    /// - Parameters:
    ///   - raw: A template string that is known to be valid.
    ///   - options: Parse options. See ``URI/Template/ParseOptions``.
    /// - Returns: A template created from the valid raw string.
    ///
    public static func valid(_ raw: String, options: ParseOptions = .init()) -> URI.Template {
      URI.Template(valid: raw, options: options)
    }

    /// Expands this template into a URI reference string using the given values.
    ///
    /// Expansion follows RFC 6570 rules for operators and modifiers, including
    /// operator-dependent percent-encoding behavior (e.g., `+`/`#` preserve
    /// reserved characters while others percent-encode). Undefined variables are
    /// ignored according to the specification.
    ///
    /// - Parameter values: A mapping from variable names to values. Scalars, lists,
    ///   and associative arrays are supported via ``URI/Template/Value``.
    /// - Returns: The expanded URI reference string.
    /// - Throws: ``URI/Template/Error-swift.enum/expansionFailed(_:)`` if expansion
    ///   fails for any reason.
    /// - SeeAlso: ``expandURI(_:requirements:)``
    ///
    public func expandString(_ values: [String: Value]) throws -> String {
      var result = String()
      result.reserveCapacity(raw.count)
      for part in parts {
        switch part {
        case .literal(let lit):
          result.append(Self.encodeLiteral(lit))
        case .expression(let expr):
          let expanded = try Self.expand(expr, with: values)
          result.append(expanded)
        }
      }
      return result
    }

    /// Expands this template and parses the result as a URI with requirements.
    ///
    /// After expansion, the resulting reference is parsed using ``URI`` with
    /// the provided requirements (e.g., ``URI/Requirement/uri`` for a strict URI,
    /// or ``URI/Requirement/iriReference`` for an IRI reference). This is a
    /// convenience to obtain a typed URI object and validate the result in one step.
    ///
    /// - Parameters:
    ///   - values: A mapping from variable names to values.
    ///   - requirements: A set of URI requirements to validate the expanded result.
    /// - Returns: A ``URI`` if expansion and parsing succeed.
    /// - Throws: ``URI/Template/Error-swift.enum/expansionFailed(_:)`` if the
    ///   expanded string does not satisfy the given requirements.
    ///
    public func expandURI(
      _ values: [String: Value],
      requirements: Set<URI.Requirement> = .uriReference
    ) throws -> URI {
      let s = try expandString(values)
      guard let uri = URI(encoded: s, requirements: requirements) else {
        throw Error.expansionFailed("Expanded string is not a valid URI for given requirements: \(s)")
      }
      return uri
    }

    // MARK: - Partial expansion

    /// Partially expands this template, preserving undefined variables.
    ///
    /// This method expands all defined variables and returns a new template that
    /// preserves any undefined variables as a residual expression. The residual
    /// operator is chosen to maintain RFC 6570 semantics (e.g., `#` becomes `+`,
    /// `?` becomes `&`).
    ///
    /// - Parameter values: A mapping from variable names to values. Undefined
    ///   variables are left in the resulting template.
    /// - Returns: A new template with defined variables expanded and undefined
    ///   variables preserved.
    /// - Throws: ``URI/Template/Error-swift.enum/expansionFailed(_:)`` if expansion fails.
    ///
    public func expandPartially(_ values: [String: Value]) throws -> Template {
      var out = String()
      out.reserveCapacity(raw.count)

      for part in parts {
        switch part {
        case .literal(let lit):
          // Preserve literal as-is (template text)
          out.append(lit)
        case .expression(let expr):
          // Separate varspecs by whether they are defined
          var definedVars: [Expression.VarSpec] = []
          var undefinedVars: [Expression.VarSpec] = []
          for v in expr.vars {
            if let val = values[v.name], val.isDefined { definedVars.append(v) } else { undefinedVars.append(v) }
          }

          if definedVars.isEmpty {
            // Keep original expression intact
            out.append(Self.expressionString(op: expr.op, vars: expr.vars))
          } else if undefinedVars.isEmpty {
            // Expand fully
            let partial = try Self.expand(Expression(op: expr.op, vars: definedVars), with: values)
            out.append(partial)
          } else {
            // Expand defined subset and then append a residual expression for undefined
            let partial = try Self.expand(Expression(op: expr.op, vars: definedVars), with: values)
            out.append(partial)

            // Choose residual op and literal separator (if needed)
            let residualOp = Self.residualOperator(for: expr.op)
            if Self.requiresLiteralSeparatorBetween(expr.op) {
              out.append(",")
            }
            out.append(Self.expressionString(op: residualOp, vars: undefinedVars))
          }
        }
      }

      return try Template(out)
    }

    static func residualOperator(for original: Expression.Operator) -> Expression.Operator {
      switch original {
      case .query: return .amp
      case .hash: return .plus
      default: return original
      }
    }

    static func requiresLiteralSeparatorBetween(_ op: Expression.Operator) -> Bool {
      switch op {
      case .none: return true
      default: return false
      }
    }

    static func expressionString(op: Expression.Operator, vars: [Expression.VarSpec]) -> String {
      var s = "{"
      if op != .none { s.append(op.rawValue) }
      for (i, v) in vars.enumerated() {
        if i > 0 { s.append(",") }
        s.append(v.name)
        if v.explode { s.append("*") }
        if let n = v.prefixLength { s.append(":\(n)") }
      }
      s.append("}")
      return s
    }

    // MARK: - Parsing

    static func parseParts(_ input: String, options: ParseOptions = .init()) throws -> [Part] {
      var parts: [Part] = []
      var i = input.startIndex
      let end = input.endIndex
      var literalStart = i

      func flushLiteral(upTo idx: String.Index) {
        if literalStart < idx {
          let lit = String(input[literalStart..<idx])
          parts.append(.literal(lit))
        }
      }

      while i < end {
        if input[i] == "{" {
          // emit any preceding literal
          flushLiteral(upTo: i)
          // find closing '}'
          guard let close = input[input.index(after: i)...].firstIndex(of: "}") else {
            throw Error.malformedTemplate("Unclosed expression", offset: input.distance(from: input.startIndex, to: i))
          }
          let body = input[input.index(after: i)..<close]
          let openingOffset = input.distance(from: input.startIndex, to: i)
          do {
            let expr = try parseExpression(String(body), at: openingOffset)
            parts.append(.expression(expr))
          } catch {
            // If policy is copyUnexpanded, append the raw expression as literal; else rethrow
            guard options.expressionErrorPolicy == .copyUnexpanded else {
              throw error
            }
            parts.append(.literal("{" + String(body) + "}"))
          }
          i = input.index(after: close)
          literalStart = i
        } else if input[i] == "}" {
          // stray closing brace
          throw Error.malformedTemplate("Stray '}'", offset: input.distance(from: input.startIndex, to: i))
        } else {
          i = input.index(after: i)
        }
      }

      // flush final literal
      flushLiteral(upTo: end)
      return parts
    }

    static func parseExpression(_ body: String, at openingOffset: Int) throws -> Expression {
      var op: Expression.Operator = .none
      var idx = body.startIndex
      let end = body.endIndex

      // operator
      if idx < end, let parsedOp = Expression.Operator(rawValue: body[idx]) {
        switch parsedOp {
        case .plus, .hash, .dot, .slash, .semicolon, .query, .amp:
          op = parsedOp
          idx = body.index(after: idx)
        case .none:
          break
        }
      }

      guard idx < end else { throw Error.emptyExpression(offset: openingOffset) }

      var vars: [Expression.VarSpec] = []
      while idx < end {
        // parse varname
        var name = String()
        name.reserveCapacity(8)
        while idx < end {
          let c = body[idx]
          if c == "," || c == "*" || c == ":" { break }
          if c == "." {
            name.append(c)
            idx = body.index(after: idx)
            continue
          }
          if c == "%" {
            // pct-encoded triplet stays in name
            guard body.distance(from: idx, to: end) >= 3,
              body[body.index(after: idx)].isHexDigit,
              body[body.index(idx, offsetBy: 2)].isHexDigit
            else {
              throw Error.invalidVarname(offset: openingOffset + body.distance(from: body.startIndex, to: idx))
            }
            name.append(contentsOf: body[idx...body.index(idx, offsetBy: 2)])
            idx = body.index(idx, offsetBy: 3)
            continue
          }
          guard c.isLetter || c.isNumber || c == "_" else { break }
          name.append(c)
          idx = body.index(after: idx)
        }
        guard !name.isEmpty else {
          throw Error.invalidVarname(offset: openingOffset + body.distance(from: body.startIndex, to: idx))
        }

        // modifier
        var explode = false
        var prefix: Int? = nil
        if idx < end {
          let c = body[idx]
          if c == "*" {
            explode = true
            idx = body.index(after: idx)
          } else if c == ":" {
            // prefix length 1..4 digits, max 9999 (RFC < 10000)
            idx = body.index(after: idx)
            let digitsStart = idx
            var digitsEnd = idx
            var count = 0
            while digitsEnd < end, count < 4, body[digitsEnd].isNumber {
              digitsEnd = body.index(after: digitsEnd)
              count += 1
            }
            guard digitsEnd > digitsStart else {
              throw Error.invalidPrefixLength(offset: openingOffset + body.distance(from: body.startIndex, to: idx))
            }
            let lenStr = body[digitsStart..<digitsEnd]
            guard let value = Int(lenStr), value > 0, value < 10000 else {
              throw Error.invalidPrefixLength(
                offset: openingOffset + body.distance(from: body.startIndex, to: digitsStart)
              )
            }
            prefix = value
            idx = digitsEnd
          }
        }

        vars.append(.init(name: name, explode: explode, prefixLength: prefix))

        if idx < end {
          let c = body[idx]
          guard c == "," else {
            // Unexpected char — the expression parser should have consumed all
            throw Error.malformedExpression(
              "Unexpected character",
              offset: openingOffset + body.distance(from: body.startIndex, to: idx)
            )
          }
          idx = body.index(after: idx)
          if idx == end {
            throw Error.malformedExpression(
              "Trailing comma",
              offset: openingOffset + body.distance(from: body.startIndex, to: idx)
            )
          }
          continue
        }
      }

      return .init(op: op, vars: vars)
    }

    // MARK: - Expansion

    struct OpSpec {
      let first: String
      let sep: String
      let named: Bool
      let ifemp: String
      let allowReserved: Bool
    }

    static func spec(for op: Expression.Operator) -> OpSpec {
      switch op {
      case .none: return .init(first: "", sep: ",", named: false, ifemp: "", allowReserved: false)
      case .plus: return .init(first: "", sep: ",", named: false, ifemp: "", allowReserved: true)
      case .hash: return .init(first: "#", sep: ",", named: false, ifemp: "", allowReserved: true)
      case .dot: return .init(first: ".", sep: ".", named: false, ifemp: "", allowReserved: false)
      case .slash: return .init(first: "/", sep: "/", named: false, ifemp: "", allowReserved: false)
      case .semicolon: return .init(first: ";", sep: ";", named: true, ifemp: "", allowReserved: false)
      case .query: return .init(first: "?", sep: "&", named: true, ifemp: "=", allowReserved: false)
      case .amp: return .init(first: "&", sep: "&", named: true, ifemp: "=", allowReserved: false)
      }
    }

    static func expand(_ expr: Expression, with values: [String: Value]) throws -> String {
      let s = spec(for: expr.op)
      var out = String()
      var didFirst = false
      var wroteOneInThisExpr = false

      func ensureFirstIfNeeded() {
        if !didFirst {
          out.append(s.first)
          didFirst = true
        }
      }

      for varspec in expr.vars {
        guard let v = values[varspec.name], v.isDefined else { continue }

        // Prefix handling for scalar only
        func applyPrefixIfNeeded(_ str: String) -> String {
          guard let n = varspec.prefixLength else { return str }
          if str.isEmpty { return str }
          // Count Unicode characters without splitting pct-triplets
          var count = 0
          var result = String()
          var i = str.startIndex
          let end = str.endIndex
          while i < end, count < n {
            let c = str[i]
            if c == "%" {
              if str.distance(from: i, to: end) >= 3,
                str[str.index(after: i)].isHexDigit,
                str[str.index(i, offsetBy: 2)].isHexDigit
              {
                result.append(contentsOf: str[i...str.index(i, offsetBy: 2)])
                i = str.index(i, offsetBy: 3)
                count += 1
                continue
              }
            }
            result.append(c)
            i = str.index(after: i)
            count += 1
          }
          return result
        }

        // Emit separator between defined varspecs
        if wroteOneInThisExpr { out.append(s.sep) }

        switch v {
        case .scalar(let raw):
          ensureFirstIfNeeded()
          let val = applyPrefixIfNeeded(raw)
          if s.named {
            out.append(encodeLiteral(varspec.name))
            if val.isEmpty { out.append(s.ifemp); wroteOneInThisExpr = true; continue }
            out.append("=")
          }
          out.append(encodeValue(val, allowReserved: s.allowReserved))
          wroteOneInThisExpr = true

        case .list(let arr):
          guard !arr.isEmpty else { continue }
          ensureFirstIfNeeded()
          if varspec.explode {
            var firstMember = true
            for m in arr {
              if !firstMember { out.append(s.sep) }
              if s.named { out.append(encodeLiteral(varspec.name)) }
              if s.named {
                if m.isEmpty {
                  out.append(s.ifemp)
                } else {
                  out.append("="); out.append(encodeValue(m, allowReserved: s.allowReserved))
                }
              } else {
                out.append(encodeValue(m, allowReserved: s.allowReserved))
              }
              firstMember = false
            }
          } else {
            if s.named {
              out.append(encodeLiteral(varspec.name))
              // a non-exploded list value is a joined list
              if arr.isEmpty { out.append(s.ifemp); wroteOneInThisExpr = true; continue }
              out.append("=")
            }
            out.append(arr.map { encodeValue($0, allowReserved: s.allowReserved) }.joined(separator: ","))
          }
          wroteOneInThisExpr = true

        case .assoc(let dict):
          // Filter out keys with undefined (nil) values and sort by key for deterministic output
          let pairs =
            dict.compactMap { (k, v) -> (String, String)? in
              guard let v = v else { return nil }
              return (k, v)
            }
            .sorted { $0.0 < $1.0 }
          guard !pairs.isEmpty else { continue }
          ensureFirstIfNeeded()
          if varspec.explode {
            var firstPair = true
            for (k, m) in pairs {
              if !firstPair { out.append(s.sep) }
              if s.named {
                // named=true for explode on assoc uses the key name
                out.append(encodeLiteral(k))
                if m.isEmpty {
                  out.append(s.ifemp)
                } else {
                  out.append("="); out.append(encodeValue(m, allowReserved: s.allowReserved))
                }
              } else {
                out.append(encodeLiteral(k))
                out.append("=")
                out.append(encodeValue(m, allowReserved: s.allowReserved))
              }
              firstPair = false
            }
          } else {
            if s.named {
              out.append(encodeLiteral(varspec.name))
              // value of the var is the concatenation of pairs name,value joined by ,
              if pairs.isEmpty { out.append(s.ifemp); wroteOneInThisExpr = true; continue }
              out.append("=")
            }
            let joined =
              pairs.map { (k, v) in
                "\(encodeLiteral(k)),\(encodeValue(v, allowReserved: s.allowReserved))"
              }
              .joined(separator: ",")
            out.append(joined)
          }
          wroteOneInThisExpr = true
        }
      }

      // If nothing defined, nothing emitted (no first prefix)
      return out
    }

    // Update internal Error to carry offsets for mapping
    static func mapToParseError(_ e: URI.Template.Error, in raw: String) -> ParseError {
      // Best-effort: compute offset by searching message hints if available later.
      switch e {
      case .malformedTemplate(let s, let off):
        return ParseError(code: .malformedTemplate, offset: off, message: s)
      case .malformedExpression(let s, let off):
        return ParseError(code: .invalidOperator, offset: off, message: s)
      case .emptyExpression(let off):
        return ParseError(code: .emptyExpression, offset: off, message: "Empty expression")
      case .invalidModifier(let off):
        return ParseError(code: .invalidModifier, offset: off, message: "Invalid modifier")
      case .invalidPrefixLength(let off):
        return ParseError(code: .invalidPrefixLength, offset: off, message: "Invalid prefix length")
      case .invalidVarname(let off):
        return ParseError(code: .invalidVarname, offset: off, message: "Invalid variable name")
      case .expansionFailed(let s):
        return ParseError(code: .malformedTemplate, offset: nil, message: s)
      case .valueTypeMismatch(let s):
        return ParseError(code: .malformedTemplate, offset: nil, message: s)
      }
    }

    // MARK: - Encoding helpers

    // Encode literal text per Section 3.1 — allowed URI chars stay; others pct-encoded.
    static func encodeLiteral(_ s: String) -> String {
      var out = String()
      out.reserveCapacity(s.utf8.count)
      var i = s.startIndex
      let end = s.endIndex
      while i < end {
        let c = s[i]
        if c == "%" {
          // pass through valid pct-encoded triplets, else encode '%'
          guard s.distance(from: i, to: end) >= 3,
            s[s.index(after: i)].isHexDigit,
            s[s.index(i, offsetBy: 2)].isHexDigit
          else {
            out.append("%25")
            i = s.index(after: i)
            continue
          }
          out.append(contentsOf: s[i...s.index(i, offsetBy: 2)])
          i = s.index(i, offsetBy: 3)
          continue
        }
        if isURIAllowedLiteral(c) {
          out.append(c)
        } else {
          // UTF-8 encode and pct-encode bytes
          for b in String(c).utf8 { out.append(percentEncodeByte(b)) }
        }
        i = s.index(after: i)
      }
      return out
    }

    static func encodeValue(_ s: String, allowReserved: Bool) -> String {
      var out = String()
      out.reserveCapacity(s.utf8.count)
      var i = s.startIndex
      let end = s.endIndex
      while i < end {
        let c = s[i]
        if c == "%" {
          // For allowReserved true, preserve valid pct-encoded triplets
          if allowReserved,
            s.distance(from: i, to: end) >= 3,
            s[s.index(after: i)].isHexDigit,
            s[s.index(i, offsetBy: 2)].isHexDigit
          {
            out.append(contentsOf: s[i...s.index(i, offsetBy: 2)])
            i = s.index(i, offsetBy: 3)
            continue
          }
          // Otherwise, % must be pct-encoded to %25
          out.append("%25")
          i = s.index(after: i)
          continue
        }
        if isUnreserved(c) || (allowReserved && isReserved(c)) {
          out.append(c)
        } else {
          for b in String(c).utf8 {
            out.append(percentEncodeByte(b))
          }
        }
        i = s.index(after: i)
      }
      return out
    }

    static func isUnreserved(_ c: Character) -> Bool {
      switch c {
      case "a"..."z", "A"..."Z", "0"..."9", "-", ".", "_", "~": return true
      default: return false
      }
    }

    static func isReserved(_ c: Character) -> Bool {
      switch c {
      case ":", "/", "?", "#", "[", "]", "@", "!", "$", "&", "'", "(", ")", "*", "+", ",", ";", "=":
        return true
      default:
        return false
      }
    }

    static func isURIAllowedLiteral(_ c: Character) -> Bool {
      // literals may include reserved, unreserved, pct-encoded (handled by encodeValue when '%')
      if isUnreserved(c) || isReserved(c) { return true }
      return false
    }

    static func percentEncodeByte(_ b: UInt8) -> String {
      let hex = "0123456789ABCDEF"
      let h = String([
        hex[hex.index(hex.startIndex, offsetBy: Int(b >> 4))], hex[hex.index(hex.startIndex, offsetBy: Int(b & 0x0F))],
      ])
      return "%" + h
    }

    // Compute level (1..4) based on usage
    static func computeLevel(parts: [Part]) -> Int {
      var level = 1
      for part in parts {
        guard case .expression(let e) = part else { continue }
        switch e.op {
        case .plus, .hash: level = max(level, 2)
        case .dot, .slash, .semicolon, .query, .amp: level = max(level, 3)
        case .none: break
        }
        if e.vars.count > 1 { level = max(level, 3) }
        if e.vars.contains(where: { $0.explode || $0.prefixLength != nil }) {
          level = max(level, 4)
        }
      }
      return level
    }
  }
}

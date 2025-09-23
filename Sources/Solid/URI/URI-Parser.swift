//
//  URI-Parser.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/25/25.
//

import SolidNet
import Foundation


extension URI {

  /// Parse a string as either a URI or IRI.
  ///
  /// - Parameters:
  ///   - string: The string to parse
  ///   - requirements: The requirements the `string` must satisfy
  /// - Returns: A URI instance if parsing succeeds, nil otherwise
  ///
  public static func parse(string: String, requirements: Set<Requirement>) -> URI? {
    var parser = Parser(string: string, requirements: requirements)
    return parser.parse()
  }

  struct Parser {

    struct ParserError: Sendable, Hashable {
      enum Code: String, Sendable {
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
      let code: Code
      let offset: Int?
      let message: String
    }

    enum Component: Hashable {
      enum PathToken {
        case slash
        case current
        case parent
      }

      case scheme(String)
      case authority
      case userInfo(user: String, password: String?)
      case hostPort(host: String, port: Int?)
      case pathToken(PathToken)
      case pathItem(String)
      case queryKey(String)
      case queryItem(key: String, value: String)
      case fragment(String)
    }

    enum State: String, Hashable {
      case scheme
      case authority
      case hostPort
      case userInfo
      case pathRoot
      case pathItem
      case queryKey
      case queryValue
      case fragment
    }

    let input: String
    let requirements: Set<Requirement>
    let allowedKinds: Set<URI.Requirement.Kind>
    let requiredRFC: URI.Requirement.RFC?
    let fragmentRequirement: URI.Requirement.Fragment
    let requiresNormalized: Bool

    var components: [Component] = []
    var states: [State] = []
    var startIndex: String.Index
    var currentIndex: String.Index

    var error: ParserError?

    init(string: String, requirements: Set<Requirement>) {
      self.input = string
      self.requirements = requirements
      self.currentIndex = string.startIndex
      self.startIndex = string.startIndex
      self.allowedKinds =
        requirements.compactMap {
          if case .kinds(let kinds) = $0 { kinds } else { nil }
        }
        .first ?? [.absolute, .relativeReference]
      self.requiredRFC =
        requirements.compactMap {
          if case .rfc(let rfc) = $0 { rfc } else { nil }
        }
        .first
      self.fragmentRequirement =
        requirements.compactMap {
          if case .fragment(let fragment) = $0 { fragment } else { nil }
        }
        .first ?? .optional
      self.requiresNormalized = requirements.contains(.normalized)
    }

    mutating func parse() -> URI? {
      let endIndex = input.endIndex

      states = [.scheme, .authority, .pathRoot, .pathItem]

      while currentIndex < endIndex {
        trace("--------")
        trace("states: \(states)")
        trace("character: \(input[currentIndex])")
        trace("components: \(components)")
        var nextStates: [State] = []
        var nextIndex = input.index(after: currentIndex)
        completed: for state in states {
          switch update(state: state) {
          case .produce(let component, nextStates: let producedNextStates, consume: let consume):
            components.append(component)
            startIndex = input.index(currentIndex, offsetBy: consume, limitedBy: endIndex) ?? endIndex
            nextIndex = startIndex
            nextStates = producedNextStates
            trace("state[\(state)] produced: \(component)")
            break completed
          case .transition(nextStates: let transitionedNextStates, consume: let consume):
            startIndex = input.index(currentIndex, offsetBy: consume, limitedBy: endIndex) ?? endIndex
            nextIndex = startIndex
            nextStates = transitionedNextStates
            break completed
          case .continue:
            nextStates.append(state)
          case .complete:
            break
          case .fail:
            return nil
          }
        }
        if nextStates.isEmpty {
          return nil
        }
        trace("nextStates: \(nextStates)")
        trace("components: \(components)")
        states = nextStates
        currentIndex = nextIndex
      }

      // Finish current states, first one to produce a component
      // is the final component to be produced
      finished: for state in states {
        switch finish(state: state) {
        case .produce(let component):
          components.append(component)
          trace("state[\(state)] produced final: \(component)")
          // Remove previous failed states
          break finished
        case .complete:
          break
        case .fail:
          return nil
        }
      }

      trace("input: \(input)")
      trace("final components: \(components)")

      return build(components: components)
    }

    func peekNext() -> Character? {
      guard
        let nextIndex = input.index(currentIndex, offsetBy: 1, limitedBy: input.endIndex),
        nextIndex < input.endIndex
      else {
        return nil
      }
      return input[nextIndex]
    }

    func peekPrevious() -> Character? {
      guard
        let previousIndex = input.index(currentIndex, offsetBy: -1, limitedBy: input.startIndex),
        previousIndex >= input.startIndex
      else {
        return nil
      }
      return input[previousIndex]
    }

    var stateOffset: Int {
      input.distance(from: startIndex, to: currentIndex)
    }

    enum StateUpdateResult {
      /// The state has succeeded in producing a component.
      ///
      /// When a encounteres a character that deterministically indicates the
      /// next possible states, and the currently tracked token is valid, it produces
      /// a component. This implicitly completes all other states that are currently
      /// possible.
      ///
      /// - Parameters:
      ///  - component: The component produced
      ///  - nextStates: The next possible states
      ///  - consume: The number of characters consumed
      ///
      case produce(Component, nextStates: [State], consume: Int = 1)

      /// The state has succeeded without producing a component.
      ///
      /// Transitions happen when a state encounters a charcter that
      /// deterministically indicates the next possible states but there is no
      /// token to be produced. Similar to ``success``, a transition implicitly
      /// completes all other states. Additionally, transitions consume no characters
      /// and the next possible states all begin at the current character.
      ///
      /// - Parameter nextStates: The next possible states
      ///
      case transition(nextStates: [State], consume: Int = 1)

      /// The state continues to be possible.
      ///
      /// Unless another current state produces a component or transition, this state
      /// continues to be considered possible.
      ///
      case `continue`

      /// The state is no longer possible.
      case complete

      /// The state has determined the next possible states but cannot produce the
      /// required component.
      ///
      /// Failure ends all parsing and the URI is invalid.
      case fail
    }

    mutating func update(state: State) -> StateUpdateResult {
      let char = input[currentIndex]
      switch state {
      case .scheme:
        if char == ":" {
          guard stateOffset > 0 else {
            return .fail
          }
          return produce(.scheme, next: [.authority, .pathRoot, .pathItem])
        } else if isSchemeChar(char, offset: stateOffset) {
          return .continue
        }
      case .authority:
        if char == "/" && peekNext() == "/" {
          return .produce(.authority, nextStates: [.pathRoot, .hostPort, .userInfo], consume: 2)
        }
      case .hostPort:
        if char == "/" {
          return produce(.hostPort, next: [.pathRoot], transition: true)
        } else if char == "?" {
          return produce(.hostPort, next: [.queryKey])
        } else if char == "#" {
          return produce(.hostPort, next: [.fragment])
        } else if isHostChar(char, offset: stateOffset) {
          return .continue
        }
      case .userInfo:
        if char == "@" {
          return produce(.userInfo, next: [.hostPort])
        } else if isUserInfoChar(char) {
          return .continue
        }
      case .pathRoot:
        if char == "/" {
          return produce(.pathRoot, next: [.pathItem], allowEmpty: true)
        }
      case .pathItem:
        let previousSlash = peekPrevious() == "/"
        if char == "?" {
          return produce(.pathItem, next: [.queryKey], allowEmpty: previousSlash)
        } else if char == "#" {
          return produce(.pathItem, next: [.fragment], allowEmpty: previousSlash)
        } else if char == "/" {
          guard !isURNState else {
            // URNs must produce a single pathItem
            return .continue
          }
          return produce(.pathItem, next: [.pathItem], allowEmpty: previousSlash)
        } else if isPathChar(char) {
          return .continue
        }
      case .queryKey:
        if char == "=" {
          return produce(.queryKey, next: [.queryValue], allowEmpty: true)
        } else if char == "&" {
          return produce(.queryKey, next: [.queryKey], allowEmpty: true)
        } else if char == "#" {
          return produce(.queryKey, next: [.fragment], allowEmpty: true)
        } else if isQueryOrFragmentChar(char) {
          return .continue
        }
      case .queryValue:
        if char == "&" {
          return produce(.queryValue, next: [.queryKey], allowEmpty: true)
        } else if char == "#" {
          return produce(.queryValue, next: [.fragment], allowEmpty: true)
        } else if isQueryOrFragmentChar(char) {
          return .continue
        }
      case .fragment:
        if isQueryOrFragmentChar(char) {
          return .continue
        }
      }
      return .complete
    }

    mutating func produce(
      _ state: State,
      next nextStates: [State],
      allowEmpty: Bool = false,
      transition: Bool = false
    ) -> StateUpdateResult {
      let consume = transition ? 0 : 1
      guard currentIndex > startIndex || allowEmpty else {
        return .transition(nextStates: nextStates, consume: consume)
      }
      let token = input[startIndex..<currentIndex]
      guard let component = component(for: state, token: token) else {
        return .fail
      }
      return .produce(component, nextStates: nextStates, consume: consume)
    }

    enum FinishResult {
      case produce(Component)
      case complete
      case fail
    }

    mutating func finish(state: State) -> FinishResult {
      currentIndex = input.endIndex
      switch state {
      case .hostPort, .pathRoot, .queryKey:
        guard currentIndex > startIndex else {
          return .complete
        }
        guard let component = component(for: state, token: input[startIndex..<currentIndex]) else {
          return .fail
        }
        return .produce(component)
      case .pathItem, .fragment, .queryValue:
        guard let component = component(for: state, token: input[startIndex..<currentIndex]) else {
          return .fail
        }
        return .produce(component)
      case .scheme, .authority, .userInfo:
        // Cannot end on these states
        return .complete
      }
    }

    mutating func component(for state: State, token: Substring) -> Component? {
      switch state {
      case .scheme:
        guard allowedKinds.contains(.absolute) else {
          error = .init(
            code: .requirementViolation,
            offset: input.distance(from: input.startIndex, to: startIndex),
            message: "Scheme not allowed for relative reference"
          )
          return nil
        }
        if requiresNormalized && !token.allSatisfy({ $0.isLowercase || !$0.isLetter }) {
          error = .init(
            code: .invalidScheme,
            offset: input.distance(from: input.startIndex, to: startIndex),
            message: "Scheme must be lowercase when normalized"
          )
          return nil
        }
        return .scheme(String(token))
      case .authority:
        guard !components.isEmpty || allowedKinds.contains(.relativeReference) else {
          return nil
        }
        return .authority
      case .userInfo:
        let tokenParts = token.split(separator: ":", maxSplits: 1)
        let user: String
        let password: String?
        if tokenParts.count == 2 {
          guard
            let decodedUser = decodePercentEncoded(tokenParts[0]),
            let decodedPassword = decodePercentEncoded(tokenParts[1])
          else {
            error = .init(
              code: .badPercentTriplet,
              offset: input.distance(from: input.startIndex, to: startIndex),
              message: "Invalid percent-encoding in user info"
            )
            return nil
          }
          user = decodedUser
          password = decodedPassword
        } else {
          guard let decodedUser = decodePercentEncoded(token) else {
            error = .init(
              code: .badPercentTriplet,
              offset: input.distance(from: input.startIndex, to: startIndex),
              message: "Invalid percent-encoding in user info"
            )
            return nil
          }
          user = decodedUser
          password = nil
        }
        return .userInfo(user: user, password: password)
      case .hostPort:
        if requiresNormalized && !token.allSatisfy({ $0.isLowercase || !$0.isLetter }) {
          error = .init(
            code: .invalidHost,
            offset: input.distance(from: input.startIndex, to: startIndex),
            message: "Host must be lowercase when normalized"
          )
          return nil
        }
        guard token.first != "[" else {
          guard let hostEnd = token.lastIndex(of: "]") else {
            error = .init(
              code: .invalidIPv6,
              offset: input.distance(from: input.startIndex, to: startIndex),
              message: "Unclosed IPv6 host"
            )
            return nil
          }
          let portToken = token[token.index(after: hostEnd)...]
          let port: Int?
          if let lastColon = portToken.lastIndex(of: ":") {
            port = Int(portToken[token.index(after: lastColon)...])
          } else {
            port = nil
          }
          let hostToken = token[token.startIndex...hostEnd]
          guard IPv6Address.parse(string: String(hostToken.dropFirst().dropLast())) != nil else {
            error = .init(
              code: .invalidIPv6,
              offset: input.distance(from: input.startIndex, to: startIndex),
              message: "Invalid IPv6 address"
            )
            return nil
          }
          return .hostPort(host: String(hostToken), port: port)
        }
        let hostToken: Substring
        let portToken: Substring?
        if let lastColon = token.lastIndex(of: ":") {
          hostToken = token[..<lastColon]
          portToken = token[token.index(after: lastColon)...]
        } else {
          hostToken = token
          portToken = nil
        }
        let port: Int?
        if let portToken {
          guard let decodedPort = Int(portToken) else {
            error = .init(
              code: .invalidPort,
              offset: input.distance(from: input.startIndex, to: startIndex),
              message: "Invalid port"
            )
            return nil
          }
          port = decodedPort
        } else {
          port = nil
        }
        guard requiredRFC == .uri else {
          guard let host = IDNHostname.parse(string: String(hostToken)) else {
            error = .init(
              code: .invalidHost,
              offset: input.distance(from: input.startIndex, to: startIndex),
              message: "Invalid IRI host"
            )
            return nil
          }
          return .hostPort(host: host.value, port: port)
        }
        guard let host = Hostname.parse(string: String(hostToken)) else {
          error = .init(
            code: .invalidHost,
            offset: input.distance(from: input.startIndex, to: startIndex),
            message: "Invalid host"
          )
          return nil
        }
        return .hostPort(host: host.value, port: port)
      case .pathRoot:
        guard !components.isEmpty || allowedKinds.contains(.relativeReference) else {
          return nil
        }
        return .pathToken(.slash)
      case .pathItem:
        // URNs are special, they can have a single path item with lenient characters
        if isURNState {
          return .pathItem(String(token))
        }
        // Check kind requirement
        guard !components.isEmpty || allowedKinds.contains(.relativeReference) else {
          return nil
        }
        guard !requiresNormalized || ((token != "." && token != "..") || isFirstPath) else {
          error = .init(
            code: .invalidPath,
            offset: input.distance(from: input.startIndex, to: startIndex),
            message: "Disallowed relative segment in normalized path"
          )
          return nil
        }
        if token == "." {
          return .pathToken(.current)
        } else if token == ".." {
          return .pathToken(.parent)
        } else if token == "/" {
          return .pathToken(.slash)
        } else {
          guard let decodedPath = decodePercentEncoded(token) else {
            error = .init(
              code: .badPercentTriplet,
              offset: input.distance(from: input.startIndex, to: startIndex),
              message: "Invalid percent-encoding in path"
            )
            return nil
          }
          return .pathItem(decodedPath)
        }
      case .queryKey:
        guard let decodedKey = decodePercentEncoded(token) else {
          error = .init(
            code: .badPercentTriplet,
            offset: input.distance(from: input.startIndex, to: startIndex),
            message: "Invalid percent-encoding in query key"
          )
          return nil
        }
        return .queryKey(decodedKey)
      case .queryValue:
        guard
          case .queryKey(let key) = components.last,
          let decodedValue = decodePercentEncoded(token)
        else {
          error = .init(
            code: .badPercentTriplet,
            offset: input.distance(from: input.startIndex, to: startIndex),
            message: "Invalid percent-encoding in query value"
          )
          return nil
        }
        components.removeLast()
        return .queryItem(key: key, value: decodedValue)
      case .fragment:
        guard let decodedFragment = decodePercentEncoded(token) else {
          error = .init(
            code: .badPercentTriplet,
            offset: input.distance(from: input.startIndex, to: startIndex),
            message: "Invalid percent-encoding in fragment"
          )
          return nil
        }
        return .fragment(decodedFragment)
      }
    }

    var isURNState: Bool {
      if components.count == 1 {
        guard case .scheme = components.first else {
          return false
        }
        return states == [.pathItem]
      } else if components.count > 1 {
        guard
          case .scheme = components[0],
          case .pathItem = components[1]
        else {
          return false
        }
        return true
      }
      return false
    }

    var isFirstPath: Bool {
      for component in components {
        switch component {
        case .pathToken, .pathItem:
          return false
        default:
          continue
        }
      }
      return true
    }

    mutating func build(components: [Component]) -> URI? {

      // Final requirement checks

      // Absolute URIs cannot end at authority separator
      if components.count == 2 && components.last == .authority {
        error = .init(code: .invalidAuthority, offset: nil, message: "Ended at authority marker")
        return nil
      }

      if requiresNormalized {
        // Check for empty path items not at beginning or end
        let pathItemComponents: [String] = components.compactMap {
          guard case .pathItem(let pathItem) = $0 else { return nil }
          return pathItem
        }
        if pathItemComponents.dropFirst().dropLast().contains("") == true {
          error = .init(code: .invalidPath, offset: nil, message: "Empty path segments not allowed in normalized form")
          return nil
        }
      }

      // Build URI from collected components
      var scheme: String?
      var authority: URI.Authority?
      var pathItems: [PathItem] = []
      var queryItems: [QueryItem]?
      var fragment: String?

      for component in components {
        switch component {
        case .scheme(let s):
          scheme = s
        case .authority:
          authority = URI.Authority(host: "", port: nil, userInfo: nil)
        case .userInfo(let u, let p):
          authority?.userInfo = URI.Authority.UserInfo(user: u, password: p)
        case .hostPort(let h, let p):
          authority?.host = h
          authority?.port = p
        case .pathToken(let t):
          switch t {
          case .slash:
            pathItems.append(.empty)
          case .current where pathItems.isEmpty:
            pathItems.append(.current)
          case .current:
            break
          case .parent where pathItems.isEmpty:
            pathItems.append(.parent)
          case .parent:
            if pathItems != [.empty] {
              pathItems.removeLast()
            }
          }
        case .pathItem(let p):
          if isURNState {
            pathItems.append(.name(p))
          } else {
            if p.isEmpty {
              guard pathItems.last != .empty else {
                continue
              }
              pathItems.append(.empty)
            } else {
              if pathItems.count > 1 && pathItems.last == .empty {
                pathItems.removeLast()
              }
              pathItems.append(.decoded(p))
            }
          }
        case .queryKey(let name):
          queryItems = (queryItems ?? []) + [QueryItem(name: name, value: nil)]
        case .queryItem(let name, let value):
          queryItems = (queryItems ?? []) + [QueryItem(name: name, value: value)]
        case .fragment(let f):
          fragment = f
        }
      }

      guard fragmentRequirement.isSatisfied(by: fragment) else {
        error = .init(code: .requirementViolation, offset: nil, message: "Fragment requirement not satisfied")
        return nil
      }

      guard let scheme else {

        guard allowedKinds.contains(.relativeReference) else {
          error = .init(code: .requirementViolation, offset: nil, message: "Expected relative reference")
          return nil
        }

        return .relative(
          authority: authority,
          path: pathItems,
          query: queryItems,
          fragment: fragment,
        )
      }

      guard allowedKinds.contains(.absolute) else {
        error = .init(code: .requirementViolation, offset: nil, message: "Expected absolute URI")
        return nil
      }

      return .absolute(
        scheme: scheme,
        authority: authority,
        path: pathItems,
        query: queryItems,
        fragment: fragment,
      )
    }

    func isSchemeChar(_ c: Character, offset: Int) -> Bool {
      if offset == 0 {
        switch c {
        case "a"..."z", "A"..."Z":
          return true
        default:
          return false
        }
      } else {
        switch c {
        case "a"..."z", "A"..."Z", "0"..."9", "+", "-", ".":
          return true
        default:
          return false
        }
      }
    }

    func isHostChar(_ c: Character, offset: Int) -> Bool {
      switch c {
      case "a"..."z", "A"..."Z", "0"..."9", "-", ".", "_", "~",    // Unreserved
        "%",    // Percent encoded
        "!", "$", "&", "'", "(", ")", "*", "+", ",", ";", "=",    // Subdelimiters
        ":":    // Additional host
        return true
      case "[" where offset == 0,
        "]" where offset != 0 && input[startIndex] == "[":
        return true
      case _ where requiredRFC != .uri:
        return c.isLetter || c.isNumber
      default:
        return false
      }
    }

    func isIPv6HostChar(_ c: Character) -> Bool {
      switch c {
      case ":", "[", "]":
        return true
      default:
        return c.isHexDigit
      }
    }

    /// Checks if the character is allowed in user or password.
    func isUserInfoChar(_ c: Character) -> Bool {
      switch c {
      case "a"..."z", "A"..."Z", "0"..."9", "-", ".", "_", "~",    // Unreserved
        "%",    // Percent encoded
        "!", "$", "&", "'", "(", ")", "*", "+", ",", ";", "=",    // Subdelimiters
        ":":    // Additional userinfo
        return true
      case _ where requiredRFC != .uri:
        return c.isLetter || c.isNumber
      default:
        return false
      }
    }

    /// Checks if the character is allowed in path components.
    func isPathChar(_ c: Character) -> Bool {
      switch c {
      case _ where isURNState:
        return true
      case "a"..."z", "A"..."Z", "0"..."9", "-", ".", "_", "~",    // Unreserved
        "%",    // Percent encoded
        "!", "$", "&", "'", "(", ")", "*", "+", ",", ";", "=",    // Subdelimiters
        ":", "@":    // Additional path
        return true
      case _ where requiredRFC != .uri:
        return c.isLetter || c.isNumber
      default:
        return false
      }
    }

    /// Checks if the character is allowed in query, or fragment.
    func isQueryOrFragmentChar(_ c: Character) -> Bool {
      switch c {
      case "a"..."z", "A"..."Z", "0"..."9", "-", ".", "_", "~",    // Unreserved
        "%",    // Percent encoded
        "!", "$", "&", "'", "(", ")", "*", "+", ",", ";", "=",    // Subdelimiters
        ":", "@",    // Additional p-char
        "/", "?":    // Additional fragment
        return true
      case _ where requiredRFC != .uri:
        // IRI mode: allow additional Unicode characters
        for scalar in c.unicodeScalars {
          switch scalar.value {
          case 0x00A0...0xD7FF,
            0xF900...0xFDCF,
            0xFDF0...0xFFEF:
            return true
          default:
            break
          }
        }
        return false
      default:
        return false
      }
    }
  }
  static func decodePercentEncoded(_ str: Substring) -> String? {
    var bytes: [UInt8] = []
    var i = str.startIndex

    while i < str.endIndex {
      let c = str[i]
      if c == "%" {
        // Ensure two more characters exist
        guard str.distance(from: i, to: str.endIndex) >= 3 else {
          return nil
        }

        let hex1 = str[str.index(after: i)]
        let hex2 = str[str.index(i, offsetBy: 2)]

        guard let hex1Value = hex1.hexDigitValue,
          let hex2Value = hex2.hexDigitValue
        else {
          return nil
        }

        let byte = UInt8(hex1Value << 4 | hex2Value)
        bytes.append(byte)

        i = str.index(i, offsetBy: 3)
      } else {
        // Append non-percent-encoded characters as UTF-8 bytes
        let scalar = String(c).utf8
        bytes.append(contentsOf: scalar)
        i = str.index(after: i)
      }
    }

    return String(bytes: bytes, encoding: .utf8)
  }
}

extension URI.Parser.Component: CustomStringConvertible {

  var description: String {
    switch self {
    case .scheme(let value): return "scheme(\(value))"
    case .authority: return "authority"
    case .userInfo(let user, let password): return "userInfo(\(user), \(password ?? "nil"))"
    case .hostPort(let host, let port): return "hostPort(\(host), \(port?.description ?? "nil"))"
    case .pathToken(let value): return "pathToken(\(value))"
    case .pathItem(let value): return "pathItem(\(value))"
    case .queryKey(let value): return "queryKey(\(value))"
    case .queryItem(let key, let value): return "queryItem(\(key)=\(value))"
    case .fragment(let value): return "fragment(\(value))"
    }
  }
}

extension URI.Parser.State: CustomStringConvertible {

  var description: String { rawValue }
}

#if TRACE_URI_PARSER
  private func trace(_ string: @autoclosure () -> String) {
    print(string())
  }
#else
  private func trace(_ string: @autoclosure () -> String) {}
#endif

//
//  URI.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/8/25.
//

import Foundation

/// A Uniform Resource Identifier (URI) that can be either absolute or a relative reference.
///
/// URIs are used to identify resources on the internet and follow the syntax defined in RFC 3986.
/// This implementation supports both absolute URIs and relative references, with comprehensive
/// support for URI manipulation and normalization.
public struct URI {

  /// Absolute URI components.
  public typealias Absolute = (
    scheme: String, authority: Authority?, path: [PathItem], query: [QueryItem]?, fragment: String?
  )
  /// Authoritative URI components.
  public typealias Authoritative = (
    scheme: String, authority: Authority, path: [PathItem], query: [QueryItem]?, fragment: String?
  )
  /// Relative reference components.
  public typealias RelativeReference = (authority: Authority?, path: [PathItem], query: [QueryItem]?, fragment: String?)

  /// The scheme component of the URI, if present.
  ///
  /// The scheme identifies the protocol used to access the resource.
  /// For example: "http", "https", "ftp", etc.
  public let scheme: String?

  /// The authority component of the URI.
  public let authority: Authority?

  /// The path component of the URI.
  public let path: [PathItem]

  /// The query component of the URI.
  public let query: [QueryItem]?

  /// The fragment component of the URI.
  public let fragment: String?

  /// Creates a new URI with the specified components.
  ///
  /// - Parameters:
  ///   - scheme: The scheme of the URI
  ///   - authority: The authority of the URI
  ///   - path: The path of the URI
  ///   - query: The query of the URI
  ///   - fragment: The fragment of the URI
  ///
  public init(
    scheme: String?,
    authority: Authority?,
    path: [PathItem],
    query: [QueryItem]?,
    fragment: String?
  ) {
    self.scheme = scheme
    self.authority = authority
    self.path = path
    self.query = query
    self.fragment = fragment
  }

  /// Creates a new URI from an encoded string, optionally applying validation requirements.
  ///
  /// This initializer parses the string and checks if it satisfies the specified requirements. If the string
  /// is invalid or does not meet the requirements, it returns nil.
  ///
  /// - Parameters:
  ///   - string: The encoded URI string to parse
  ///   - requirements: A set of requirements that the URI must satisfy
  ///
  public init?(encoded string: String, requirements: Set<Requirement> = []) {
    guard let uri = URI.parse(string: string, requirements: requirements) else {
      return nil
    }
    self = uri
  }

  /// Creates a new URI from an encoded string, optionally applying validation requirements.
  ///
  /// - Parameters:
  ///   - string: The encoded URI string to parse
  ///   - requirements: A variadic list of requirements that the URI must satisfy
  ///
  public init?(encoded string: String, requirements: Requirement...) {
    self.init(encoded: string, requirements: Set(requirements))
  }

  /// Creates a new URI from a string that is known to be valid.
  ///
  /// - Parameter valid: A string that is known to be a valid URI
  /// - Warning: This initializer will crash if the string is not a valid URI
  public init(valid: String) {
    guard let uri = URI(encoded: valid) else {
      fatalError("Invalid URI: \(valid)")
    }
    self = uri
  }

  /// Creates a new URI from a string that is known to be valid.
  ///
  /// - Parameter valid: A string that is known to be a valid URI
  /// - Returns: A new URI
  /// - Warning: This function will crash if the string is not a valid URI
  public static func valid(_ valid: String) -> URI {
    return URI(valid: valid)
  }

  /// Creates a new URI from a URL.
  ///
  /// - Parameters:
  ///   - url: The URL to convert to a URI
  ///   - requirements: A set of requirements that the URI must satisfy
  ///
  public init?(url: URL, requirements: Set<Requirement> = []) {
    guard let uri = URI.parse(string: url.absoluteString, requirements: requirements) else {
      return nil
    }
    self = uri
  }

  /// Creates a new absolute URI.
  ///
  /// - Parameters:
  ///   - scheme: The scheme of the URI
  ///   - authority: The authority of the URI
  ///   - path: The path of the URI
  ///   - query: The query of the URI
  ///   - fragment: The fragment of the URI
  /// - Returns: An absolute URI with the specified components
  public static func absolute(
    scheme: String,
    authority: Authority? = nil,
    path: [PathItem] = [],
    query: [QueryItem]? = nil,
    fragment: String? = nil,
  ) -> Self {
    Self(
      scheme: scheme,
      authority: authority,
      path: path,
      query: query,
      fragment: fragment
    )
  }

  /// Creates a new absolute URI from an encoded path.
  ///
  /// - Parameters:
  ///   - scheme: The scheme of the URI
  ///   - authority: The authority of the URI
  ///   - encodedPath: The encoded path of the URI
  ///   - query: The query of the URI
  ///   - fragment: The fragment of the URI
  /// - Returns: An absolute URI with the specified components
  public static func absolute(
    scheme: String,
    authority: Authority? = nil,
    encodedPath: String,
    query: [QueryItem]? = nil,
    fragment: String? = nil
  ) -> URI {
    Self(
      scheme: scheme,
      authority: authority,
      path: [URI.PathItem].from(encoded: encodedPath, absolute: true),
      query: query,
      fragment: fragment
    )
  }

  /// Creates a new relative reference.
  ///
  /// - Parameters:
  ///  - authority: The authority of the URI
  ///  - path: The path of the URI
  ///  - query: The query of the URI
  ///  - fragment: The fragment of the URI
  /// - Returns: A relative reference with the specified components
  public static func relative(
    authority: Authority? = nil,
    path: [PathItem] = [],
    query: [QueryItem]? = nil,
    fragment: String? = nil
  ) -> URI {
    Self(
      scheme: nil,
      authority: authority,
      path: path,
      query: query,
      fragment: fragment
    )
  }

  /// Creates a relative reference from an encoded path.
  ///
  /// - Parameters:
  ///  - authority: The authority of the URI
  ///  - encodedPath: The encoded path of the URI
  ///  - query: The query of the URI
  ///  - fragment: The fragment of the URI
  public static func relative(
    authority: URI.Authority? = nil,
    encodedPath: String,
    query: [URI.QueryItem]? = nil,
    fragment: String? = nil
  ) -> Self {
    Self(
      scheme: nil,
      authority: authority,
      path: [URI.PathItem].from(encoded: encodedPath, absolute: false),
      query: query,
      fragment: fragment
    )
  }

  /// The encoded authority of the URI.
  ///
  /// This property returns the authority in its encoded form, ready for use in HTTP requests
  /// or other contexts where a string representation is needed.
  public var encodedAuthority: String? {
    guard let authority else {
      return nil
    }
    return authority.encoded
  }

  /// The encoded path of the URI.
  ///
  /// This property returns the path in its encoded form, ready for use in HTTP requests
  /// or other contexts where a string representation is needed.
  public var encodedPath: String {
    return path.encoded(relative: isRelativeReference)
  }

  /// The encoded query of the URI.
  ///
  /// This property returns the query in its encoded form, ready for use in HTTP requests
  /// or other contexts where a string representation is needed.
  public var encodedQuery: String? {
    guard let query else {
      return nil
    }
    return query.encoded
  }

  /// The encoded fragment of the URI.
  ///
  /// This property returns the fragment in its encoded form, ready for use in HTTP requests
  /// or other contexts where a string representation is needed.
  public var encodedFragment: String? {
    guard let fragment else {
      return nil
    }
    return fragment.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
  }

  /// The encoded string representation of the URI.
  ///
  /// This property returns the URI in its encoded form, ready for use in HTTP requests
  /// or other contexts where a string representation is needed.
  public var encoded: String {
    let authority =
      if let encodedAuthority = self.encodedAuthority {
        "//\(encodedAuthority)"
      } else {
        ""
      }
    let path = self.encodedPath
    let query =
      if let encodedQuery = self.encodedQuery {
        "?\(encodedQuery)"
      } else {
        ""
      }
    let fragment =
      if let encodedFragment = self.encodedFragment {
        "#\(encodedFragment)"
      } else {
        ""
      }
    guard let scheme else {
      return "\(authority)\(path)\(query)\(fragment)"
    }
    return "\(scheme):\(authority)\(path)\(query)\(fragment)"
  }

  /// Indicates whether the URI is absolute (has a scheme).
  ///
  /// An absolute URI begins with a scheme followed by a colon.
  public var isAbsolute: Bool {
    scheme != nil
  }

  /// The absolute URI, if this is an absolute URI.
  public var absolute: Absolute? {
    guard let scheme else {
      return nil
    }
    return (scheme: scheme, authority: authority, path: path, query: query, fragment: fragment)
  }

  /// Indicates whether the URI is an authoritative URI.
  ///
  /// An authoritative URI has a scheme and authority.
  public var isAuthoritative: Bool {
    guard scheme != nil, authority != nil else {
      return false
    }
    return true
  }

  /// The authoritative URI, if this is an authoritative URI.
  public var authoritative: Authoritative? {
    guard let scheme, let authority else {
      return nil
    }
    return (scheme: scheme, authority: authority, path: path, query: query, fragment: fragment)
  }

  /// Indicates whether the URI is a relative reference.
  ///
  /// A relative reference does not begin with a scheme and colon.
  public var isRelativeReference: Bool {
    scheme == nil
  }

  /// The relative reference, if this is a relative reference.
  public var relativeReference: RelativeReference? {
    guard scheme == nil else {
      return nil
    }
    return (authority: authority, path: path, query: query, fragment: fragment)
  }

  /// Indicates whether the URI is in its normalized form.
  ///
  /// A normalized URI has:
  /// - Lowercase scheme
  /// - Lowercase host
  /// - Percent-encoded components
  /// - No empty path segments
  /// - No trailing slash unless it's the root path
  public var isNormalized: Bool {
    if let scheme, scheme != scheme.lowercased() {
      return false
    }
    if let authority, !authority.isNormalized {
      return false
    }
    return path.isNormalized
  }

  /// Indicates whether the URI is properly percent encoded.
  ///
  /// A properly percent encoded URI has:
  /// - All reserved characters percent encoded
  /// - All non-ASCII characters percent encoded
  /// - No invalid percent encoding sequences
  public var isPercentEncoded: Bool {
    if let authority, !authority.isPercentEncoded {
      return false
    }
    if let query, !query.allSatisfy({ $0.isPercentEncoded }) {
      return false
    }
    if let fragment {
      guard fragment.rangeOfCharacter(from: .urlFragmentAllowed.inverted) == nil else {
        return false
      }
    }
    return true
  }

  /// Returns a normalized version of this URI.
  ///
  /// Normalization includes:
  /// - Converting scheme to lowercase
  /// - Converting host to lowercase
  /// - Percent-encoding components
  /// - Removing empty path segments
  /// - Removing trailing slash unless it's the root path
  /// - Sorting query parameters
  ///
  /// ### Path Normalization
  ///
  /// #### Empty Segment Retention (Preserving Slashes)
  /// Path normalization retains leading and trailing empty segments
  /// to preserve slashes. `retainTrailingEmptySegment` argument can
  /// be used to remove empty trailing segments.
  ///
  /// #### Leading Relative Segment Retention
  /// When the URI is a relative reference, path normalization retains
  /// the leading current (`.`) & parent (`..`) segments, as is common for relative
  /// references. If you wish to remove these segmente, you need to
  /// normalize the path manually using
  /// ``PathItem/normalized(retainLeadingRelativeSegments:retainTrailingEmptySegment:)``.
  ///
  /// - Parameter retainTrailingEmptySegment: Whether to retain trailing empty segments to
  ///   preserve slashes. Defaults to `true`.
  /// - Returns: A normalized URI
  ///
  public func normalized(retainTrailingEmptySegment: Bool = true) -> URI {
    Self(
      scheme: scheme?.lowercased(),
      authority: authority?.normalized(),
      path:
        path
        .normalized(
          retainLeadingRelativeSegments: isRelativeReference,
          retainTrailingEmptySegment: retainTrailingEmptySegment
        ),
      query: query,
      fragment: fragment
    )
  }

  /// Retrieves a specific query item by name, if present.
  ///
  /// - Parameter named: The name of the query item to retrieve
  /// - Returns: The query item if found, nil otherwise
  ///
  public func queryItem(named: String) -> QueryItem? {
    query?.first { $0.name == named }
  }

  /// Updates the specified components of this URI.
  ///
  /// Creates a new URI with the specified components updated, leaving the
  /// other components unchanged.
  ///
  /// - Parameter components: The components to update
  /// - Returns: A new URI with the specified components updated
  ///
  public func updating(_ components: some Sequence<Component>) -> URI {
    var result = self
    for component in components {
      switch component {
      case .scheme(let scheme):
        result = Self(
          scheme: scheme,
          authority: authority,
          path: path,
          query: query,
          fragment: fragment
        )
      case .host(let host):
        result = Self(
          scheme: scheme,
          authority: authority?.copy(host: host),
          path: path,
          query: query,
          fragment: fragment
        )
      case .port(let port):
        result = Self(
          scheme: scheme,
          authority: authority?.copy(port: port),
          path: path,
          query: query,
          fragment: fragment
        )
      case .user(let user):
        result = Self(
          scheme: scheme,
          authority: authority?.copy(userInfo: authority?.userInfo?.copy(user: user)),
          path: path,
          query: query,
          fragment: fragment
        )
      case .password(let password):
        result = Self(
          scheme: scheme,
          authority: authority?.copy(userInfo: authority?.userInfo?.copy(password: password)),
          path: path,
          query: query,
          fragment: fragment
        )
      case .path(let path):
        result = Self(
          scheme: scheme,
          authority: authority,
          path: path,
          query: query,
          fragment: fragment
        )
      case .query(let query):
        result = Self(
          scheme: scheme,
          authority: authority,
          path: path,
          query: query,
          fragment: fragment
        )
      case .fragment(let fragment):
        result = Self(
          scheme: scheme,
          authority: authority,
          path: path,
          query: query,
          fragment: fragment
        )
      }
    }
    return result
  }

  /// Updates the specified components of this URI.
  ///
  /// Creates a new URI with the specified components updated, leaving the
  /// other components unchanged.
  ///
  /// - Parameter components: The components to update
  /// - Returns: A new URI with the specified components updated
  ///
  public func updating(_ components: Component...) -> URI {
    updating(components)
  }

  /// Removes the specified parts from this absolute URI.
  ///
  /// Creates a new URI with the specified parts removed, leaving the
  /// other components unchanged.
  ///
  /// - Parameter components: The parts to remove
  /// - Returns: A new absolute URI with the specified parts removed
  ///
  public func removing(_ components: some Sequence<Component.Kind>) -> URI {
    var result = self
    for part in components {
      switch part {
      case .user:
        result = Self(
          scheme: scheme,
          authority: authority?.copy(userInfo: authority?.userInfo?.copy(user: .some(nil))),
          path: path,
          query: query,
          fragment: fragment
        )
      case .password:
        result = Self(
          scheme: scheme,
          authority: authority?.copy(userInfo: authority?.userInfo?.copy(password: .some(nil))),
          path: path,
          query: query,
          fragment: fragment
        )
      case .port:
        result = Self(
          scheme: scheme,
          authority: authority?.copy(port: .some(nil)),
          path: path,
          query: query,
          fragment: fragment
        )
      case .path:
        result = Self(
          scheme: scheme,
          authority: authority,
          path: [],
          query: query,
          fragment: fragment
        )
      case .query:
        result = Self(
          scheme: scheme,
          authority: authority,
          path: path,
          query: nil,
          fragment: fragment
        )
      case .fragment:
        result = Self(
          scheme: scheme,
          authority: authority,
          path: path,
          query: query,
          fragment: nil
        )
      default:
        break
      }
    }
    return result
  }

  /// Removes the specified parts from this absolute URI.
  ///
  /// Creates a new URI with the specified parts removed, leaving the
  /// other components unchanged.
  ///
  /// - Parameter components: The parts to remove
  /// - Returns: A new absolute URI with the specified parts removed
  ///
  public func removing(_ components: Component.Kind...) -> URI {
    removing(Set(components))
  }

  /// Resolves this URI against a base URI.
  ///
  /// - Parameter base: The base URI to resolve against
  /// - Returns: A new absolute URI
  public func resolved(against base: URI) -> URI {
    if isAbsolute {
      return self
    }
    guard let base = base.absolute else {
      return self
    }

    let selfPath = path
    let basePath = base.path.normalized(retainLeadingRelativeSegments: false, retainTrailingEmptySegment: true)

    var absPath: [URI.PathItem]

    if selfPath.isEmpty {
      absPath = basePath
    } else if basePath.isEmpty || (selfPath.count > 1 && selfPath.first == .empty) {
      absPath = selfPath.first == .empty ? selfPath : [.empty] + selfPath
    } else {
      // Drops the .empty segment for directories and the last segment for files
      let mergePath = basePath.count > 1 ? basePath.dropLast() : basePath
      var resPath: [URI.PathItem] = mergePath.first != .empty ? [.empty] + mergePath : mergePath
      for component in selfPath {
        switch component {
        case .current:
          // skip
          break
        case .parent:
          if resPath != [.empty] {
            resPath = resPath.dropLast()
          }
        default:
          resPath.append(component)
        }
      }
      absPath = resPath
    }

    let query = self.query ?? base.query
    let fragment = self.fragment ?? base.fragment

    return Self(
      scheme: base.scheme,
      authority: base.authority,
      path: absPath,
      query: query,
      fragment: fragment
    )
  }

  /// Resolves this URI against a base URI string.
  ///
  /// - Parameter base: The base URI string to resolve against
  /// - Returns: A new absolute URI, or nil if the base string is invalid
  ///
  public func resolved(against base: String) -> URI? {
    guard let baseURI = URI(encoded: base) else {
      return nil
    }
    return resolved(against: baseURI)
  }

  /// Creates a relative URI from this absolute URI.
  ///
  /// This method computes the relative URI from this URI to the specified
  /// URI and returns the computed relative URI.
  ///
  /// - Parameter absolute: The absolute URI to make relative to
  /// - Returns: A new relative URI
  ///
  public func relative(to absolute: URI) -> URI {
    guard let absSelf = self.absolute, let absBase = absolute.absolute else {
      return self
    }

    let selfPath = path
    let basePath = absBase.path

    guard
      absSelf.scheme == absBase.scheme,
      absSelf.authority == absBase.authority,
      selfPath.count >= basePath.count
    else {
      return self
    }

    var commonPrefixCount = 0
    while commonPrefixCount < min(selfPath.count, basePath.count),
      selfPath[commonPrefixCount] == basePath[commonPrefixCount]
    {
      commonPrefixCount += 1
    }

    let relPath = Array([.current] + selfPath.dropFirst(commonPrefixCount))
    let query = absSelf.query ?? absBase.query
    let fragment = absSelf.fragment ?? absBase.fragment

    return Self(
      scheme: nil,
      authority: nil,
      path: relPath,
      query: query,
      fragment: fragment
    )
  }

  /// Creates a relative URI from this absolute URI.
  ///
  /// This method computes the relative URI from this URI to the specified
  /// URI and returns the computed relative URI.
  ///
  /// - Parameter absolute: The absolute URI string to make relative to
  /// - Returns: A new relative URI, or nil if the absolute string is invalid
  ///
  public func relative(to absolute: String) -> URI? {
    guard let absoluteURI = URI(encoded: absolute) else {
      return nil
    }
    return relative(to: absoluteURI)
  }

  /// The transform to use when creating relative paths from absolute URIs.
  ///
  public enum RelativePathTransform {

    /// Return the path unaltered if it is already relative,
    /// or convert it to a path relative to the root directory.
    case relative

    /// Return the path unaltered if it is already absolute,
    /// or convert it to an absolute path relative to the root directory.
    case absolute

    /// If relative, return the path relative to the current directory,
    /// or convert the entire absolute path to a relative path from the
    /// current directory.
    case directory
  }

  /// Creates a relative URI from this URI, possible transforming it.
  ///
  /// If this URI is absolute, it will be converted to a relative URI using the specified
  /// path transoformation style. If this URI is already relative, it will be returned as-is.
  ///
  /// - SeeAlso: ``RelativePathTransform``
  /// - Parameter pathTransform: The transform to use when creating a relative path from absolute URIs.
  /// - Returns: A new URI with a relative path
  ///
  public func relative(pathTransform: RelativePathTransform = .directory) -> URI {
    if isRelativeReference {
      return self
    }

    let path =
      switch pathTransform {
      case .absolute: path.absolute
      case .relative: path.relative
      case .directory: path.directoryRelative
      }

    return URI(
      scheme: nil,
      authority: nil,
      path: path,
      query: query,
      fragment: fragment
    )
  }

  /// Returns a new URI ensuring the path components are normalized to a directory path.
  ///
  /// This method returns a new URI with the path components normalized to a directory path
  /// (i.e., ensuring it has a trailing slash). All other components are left unchanged.
  ///
  /// - Returns: A new URI with the path components normalized to a directory path
  ///
  public func directoryPath() -> URI {
    Self(
      scheme: scheme,
      authority: authority,
      path: path.last == .empty ? path : path + [.empty],
      query: query,
      fragment: fragment
    )
  }

}

extension URI: Sendable {}
extension URI: Hashable {}
extension URI: Equatable {}

extension URI: CustomStringConvertible, CustomDebugStringConvertible {

  /// A textual representation of the URI.
  public var description: String { encoded }

  /// A textual representation of the URI, suitable for debugging.
  public var debugDescription: String { encoded }

}

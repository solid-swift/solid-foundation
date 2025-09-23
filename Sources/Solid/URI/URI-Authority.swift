//
//  URI-Authority.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/26/25.
//

extension URI {

  /// The authority component of a URI.
  ///
  /// The authority component contains user information, host, and port.
  /// It appears after the scheme and before the path in a URI.
  ///
  public struct Authority {

    /// User information for the authority component.
    ///
    /// Contains the username and password for authentication.
    ///
    public struct UserInfo {

      /// The username, if present.
      public var user: String?
      /// The password, if present.
      public var password: String?

      /// Creates a new UserInfo instance.
      ///
      /// - Parameters:
      ///   - user: The username
      ///   - password: The password
      ///
      public init(user: String?, password: String?) {
        self.user = user
        self.password = password
      }
    }

    /// The host name or IP address.
    public var host: String
    /// The port number, if specified.
    public var port: Int?
    /// The user information, if present.
    public var userInfo: UserInfo?

    /// Creates a new Authority instance.
    ///
    /// - Parameters:
    ///   - host: The host name or IP address
    ///   - port: The port number
    ///   - userInfo: The user information
    ///
    public init(host: String, port: Int?, userInfo: UserInfo?) {
      self.host = host
      self.port = port
      self.userInfo = userInfo?.emptyToNil
    }
  }

}

extension URI.Authority: Sendable {}
extension URI.Authority: Hashable {}
extension URI.Authority: Equatable {}

extension URI.Authority {

  /// Creates a new ``URI/Authority`` instance.
  ///
  /// - Parameters:
  ///   - host: The host name or IP address
  ///   - port: The port number, or `nil` if the default port for the scheme should be used
  ///   - userInfo: The user information, or `nil` if the authority is not protected by user information
  /// - Returns: A new Authority instance
  ///
  public static func from(host: String, port: Int? = nil, userInfo: UserInfo? = nil) -> Self {
    Self(host: host, port: port, userInfo: userInfo)
  }

  /// Creates a new ``URI/Authority`` instance, if one or more of the parameters are provided.
  ///
  /// - Parameters:
  ///   - host: The host name or IP address
  ///   - port: The port number, or `nil` if the default port for the scheme should be used
  ///   - userInfo: The user information, or `nil` if the authority is not protected by user information
  /// - Returns: A new Authority instance if at least one of the parameters is provided, otherwise `nil`
  ///
  public static func from(host: String?, port: Int? = nil, userInfo: UserInfo? = nil) -> Self? {
    guard host != nil || port != nil || userInfo != nil else {
      return nil
    }
    return Self(host: host ?? "", port: port, userInfo: userInfo)
  }

  /// Creates a copy of this ``URI/Authority`` with one or more properties updated.
  ///
  /// - Parameters:
  ///   - host: The new host name or IP address, or `nil` to leave the host name unchanged
  ///   - port: The new port number, or `nil` to leave the port number unchanged
  ///   - userInfo: The new user information, or `nil` to leave the user information unchanged
  /// - Returns: A new Authority instance with the specified properties updated.
  ///
  public func copy(
    host: String? = nil,
    port: Int?? = nil,
    userInfo: UserInfo?? = nil
  ) -> Self {
    Self(
      host: host ?? self.host,
      port: port ?? self.port,
      userInfo: userInfo ?? self.userInfo
    )
  }

  /// Creates a new ``URI/Authority`` instance with the given hostname or IP address and
  /// optionally, a port number and user information.
  ///
  /// - Parameters:
  ///   - host: The host name or IP address
  ///   - port: The port number, or `nil` to use the default port for the scheme
  ///   - userInfo: The user information, or `nil` to use no user information
  /// - Returns: A new Authority instance
  public static func host(
    _ host: String,
    port: Int? = nil,
    _ userInfo: URI.Authority.UserInfo? = nil
  ) -> Self {
    Self(host: host, port: port, userInfo: userInfo)
  }

  /// The encoded host name or IP address.
  ///
  /// - Returns: The encoded host name or IP address
  public var encodedHost: String {
    host.lowercased().addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? ""
  }

  /// Encoded version of the authority.
  public var encoded: String {
    let hostPort = "\(encodedHost)\(port.map { ":\($0)" } ?? "")"
    guard let userInfo else {
      return hostPort
    }
    return "\(userInfo.encoded)@\(hostPort)"
  }

  /// Indicates whether this query item is properly percent encoded.
  ///
  /// A properly percent encoded authority has:
  /// - All reserved characters in host and userInfo percent encoded
  /// - All non-ASCII characters in host and userInfo percent encoded
  /// - No invalid percent encoding sequences
  public var isPercentEncoded: Bool {
    guard host.rangeOfCharacter(from: .urlHostAllowed.inverted) == nil else { return false }
    if let userInfo {
      guard userInfo.isPercentEncoded else { return false }
    }
    return true
  }

  /// Indicates whether this authority is normalized according to RFC 3986.
  ///
  /// A normalized authority has:
  /// - A lowercase host name
  /// - No empty port (nil instead)
  /// - A normalized userInfo if present
  public var isNormalized: Bool {
    // No empty port is obeyed by port being an Int?, which is either nil or an integer.
    host == host.lowercased() && (userInfo?.isNormalized ?? true)
  }

  /// Returns a normalized version of this authority.
  ///
  /// A normalized authority has:
  /// - A lowercase host name
  /// - No empty port (nil instead)
  /// - A normalized userInfo if present
  ///
  /// - Returns: A new normalized authority
  public func normalized() -> Self {
    Self(
      host: host.lowercased(),
      port: port,
      userInfo: userInfo?.normalized()
    )
  }
}

extension URI.Authority.UserInfo: Sendable {}
extension URI.Authority.UserInfo: Hashable {}
extension URI.Authority.UserInfo: Equatable {}

extension URI.Authority.UserInfo {

  /// Creates a new ``URI/Authority/UserInfo-swift.struct`` instance, if one or more of the parameters are provided.
  ///
  /// - Parameters:
  ///   - user: The username
  ///   - password: The password
  /// - Returns: A new UserInfo instance if at least one of the parameters is provided, otherwise `nil`
  ///
  public static func from(user: String?, password: String?) -> Self? {
    Self(user: user, password: password).emptyToNil
  }

  /// Creates a copy of this ``URI/Authority/UserInfo`` instance with one or more properties updated.
  ///
  /// - Parameters:
  ///   - user: The new username, or `nil` to leave the username unchanged
  ///   - password: The new password, or `nil` to leave the password unchanged
  /// - Returns: A new Authority instance with the specified properties updated.
  ///
  public func copy(
    user: String?? = nil,
    password: String?? = nil
  ) -> Self? {
    Self(
      user: user ?? self.user,
      password: password ?? self.password
    )
    .emptyToNil
  }

  /// Creates a new ``URI/Authority/UserInfo-swift.struct`` instance with the given username.
  ///
  /// - Parameter user: The username
  /// - Returns: A new UserInfo instance
  ///
  public static func user(_ user: String) -> Self {
    Self(user: user, password: nil)
  }

  /// Creates a new ``URI/Authority/UserInfo-swift.struct`` instance with the given username and password.
  ///
  /// - Parameters:
  ///   - user: The username
  ///   - password: The password
  /// - Returns: A new UserInfo instance
  ///
  public static func user(_ user: String, password: String) -> Self {
    Self(user: user, password: password)
  }

  /// Returns `nil` if the all the propertiees are empty, otherwise returns this user unchanged.
  ///
  /// - Returns: `nil` if the user info is empty, otherwise the user info itself
  ///
  public var emptyToNil: Self? {
    guard user != nil || password != nil else {
      return nil
    }
    return self
  }

  /// The encoded username.
  ///
  /// - Returns: The encoded username, or `nil` if the username is empty
  ///
  public var encodedUser: String? {
    user?.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed)
  }

  /// The encoded password.
  ///
  /// - Returns: The encoded password, or `nil` if the password is empty
  ///
  public var encodedPassword: String? {
    password?.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed)
  }

  /// The encoded user info.
  ///
  /// - Returns: The encoded user info, or `nil` if the user info is empty
  ///
  public var encoded: String {
    return switch (encodedUser, encodedPassword) {
    case (.some(let user), .some(let password)): "\(user):\(password)"
    case (.some(let user), .none): user
    case (.none, .some(let password)): ":\(password)"
    default: ""
    }
  }

  /// Indicates whether this user info is properly percent encoded.
  ///
  /// A properly percent encoded user info has:
  /// - All reserved characters in user and password percent encoded
  /// - All non-ASCII characters in user and password percent encoded
  /// - No invalid percent encoding sequences
  public var isPercentEncoded: Bool {
    if let user {
      guard user.rangeOfCharacter(from: .urlUserAllowed.inverted) == nil else { return false }
    }
    if let password {
      guard password.rangeOfCharacter(from: .urlPasswordAllowed.inverted) == nil else { return false }
    }
    return true
  }

  /// Indicates whether this user info is normalized.
  ///
  /// A normalized user info has:
  /// - All unreserved characters decoded
  /// - All reserved characters percent encoded
  /// - All percent encodings are uppercase
  /// - No percent encoding of unreserved characters
  public var isNormalized: Bool {
    if let user {
      guard user == user.removingPercentEncoding?.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) else {
        return false
      }
      guard !user.contains(where: { $0.isASCII && $0.isLetter && $0.isLowercase }) else {
        return false
      }
    }

    if let password {
      guard
        password == password.removingPercentEncoding?.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed)
      else {
        return false
      }
      guard !password.contains(where: { $0.isASCII && $0.isLetter && $0.isLowercase }) else {
        return false
      }
    }

    return true
  }

  /// Returns a normalized version of this user info.
  ///
  /// A normalized user info has:
  /// - All unreserved characters decoded
  /// - All reserved characters percent encoded
  /// - All percent encodings are uppercase
  /// - No percent encoding of unreserved characters
  ///
  /// - Returns: A new normalized user info
  public func normalized() -> Self {
    let normalizedUser = user.map { user in
      user.removingPercentEncoding?
        .addingPercentEncoding(withAllowedCharacters: .urlUserAllowed)?
        .uppercased() ?? user
    }

    let normalizedPassword = password.map { password in
      password.removingPercentEncoding?
        .addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed)?
        .uppercased() ?? password
    }

    return Self(user: normalizedUser, password: normalizedPassword)
  }
}

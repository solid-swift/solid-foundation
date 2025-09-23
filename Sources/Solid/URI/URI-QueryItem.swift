//
//  URI-QueryItem.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/25/25.
//

extension URI {

  /// A query item in a URI.
  ///
  /// Query items can be a name-value pair or a flag (i.e., a name with no value) that appears after the
  /// question mark in a URI, such as "name=value" in "?name=value" or "?flag" in "?flag".
  public struct QueryItem {

    /// The name of the query item.
    public var name: String
    /// The value of the query item, if present.
    public var value: String?

    /// Creates a new query item with the given name and value.
    ///
    /// - Parameters:
    ///   - name: The name of the query item
    ///   - value: The value of the query item
    public init(name: String, value: String?) {
      self.name = name
      self.value = value
    }
  }

}

extension URI.QueryItem: Sendable {}
extension URI.QueryItem: Hashable {}
extension URI.QueryItem: Equatable {}

extension URI.QueryItem {

  /// Creates a query item from optional name and value.
  ///
  /// - Parameters:
  ///   - name: The name of the query item
  ///   - value: The value of the query item
  /// - Returns: A query item if the name is not nil, nil otherwise
  public static func from(name: String?, value: String?) -> Self? {
    guard let name else {
      return nil
    }
    return Self(name: name, value: value)
  }

  /// Creates a flag query item.
  ///
  /// - Note: A flag query item is a query item with no value.
  ///
  /// - Parameter name: The name of the flag
  /// - Returns: A query item with the given name and no value
  public static func flag(_ name: String) -> Self {
    Self(name: name, value: nil)
  }

  /// Creates a boolean flag query item.
  ///
  /// A boolean flag query item is a query item with a name and a boolean value,
  /// as opposed to a `flag` query item which has no value.
  ///
  /// - Parameters:
  ///   - name: The name of the flag
  ///   - value: The boolean value
  /// - Returns: A query item with the given name and value as "true" or "false"
  public static func flag(_ name: String, value: Bool) -> Self {
    Self(name: name, value: value ? "true" : "false")
  }

  /// Creates a query item with a name and value.
  ///
  /// - Parameters:
  ///   - name: The name of the query item
  ///   - value: The value of the query item
  /// - Returns: A query item with the given name and value
  public static func name(_ name: String, value: String) -> Self {
    Self(name: name, value: value)
  }

  /// Creates a query item with a name and optional value.
  ///
  /// - Parameters:
  ///   - name: The name of the query item
  ///   - value: The value of the query item
  /// - Returns: A query item with the given name and value
  public static func name(_ name: String, value: String?) -> Self {
    Self(name: name, value: value)
  }

  /// The encoded name of the query item.
  ///
  /// - Returns: The encoded name of the query item
  public var encodedName: String {
    name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
  }

  /// The encoded value of the query item.
  ///
  /// - Returns: The encoded value of the query item, or nil if the value is nil
  public var encodedValue: String? {
    value?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
  }

  /// The encoded form of the query item.
  ///
  /// The encoded form is the encoded name and value separated by an equals sign,
  /// or just the encoded name if the value is nil.
  ///
  /// - Returns: The encoded form of the query item, or nil if the value is nil
  public var encoded: String {
    let name = encodedName
    guard let value = encodedValue else {
      return name
    }
    return "\(name)=\(value)"
  }

  /// Indicates whether this query item is properly percent encoded.
  ///
  /// A properly percent encoded query item has:
  /// - All reserved characters percent encoded
  /// - All non-ASCII characters percent encoded
  /// - No invalid percent encoding sequences
  public var isPercentEncoded: Bool {
    guard name.rangeOfCharacter(from: .urlQueryAllowed.inverted) == nil else { return false }
    if let value {
      guard value.rangeOfCharacter(from: .urlQueryAllowed.inverted) == nil else { return false }
    }
    return true
  }

}

extension Array where Element == URI.QueryItem {

  /// The encoded form of the query items.
  ///
  /// The encoded form is the encoded query items separated by an ampersand.
  ///
  /// - Returns: The encoded form of the query items
  public var encoded: String {
    map(\.encoded).joined(separator: "&")
  }

}

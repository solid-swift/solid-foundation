//
//  Path.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/25/25.
//

/// RFC-9535 Path for ``Value`` instances.
///
/// Paths allow querying and navigating the JSON-like ``Value``s using the standardized
/// JSONPath syntax.
///
/// Example:
/// ```swift
/// let value: Value = [
///   "name": "John",
///   "age": 30,
///   "address": [
///     "name": "Home",
///     "street": "123 Main St",
///     "city": "Anytown",
///     "zip": "12345"
///   ]
/// ]
/// let path = Path("$..name")
/// let results = value[path]
/// // results == ["John", "Home"]
/// ```
/// Path implements the entire JSONPath syntax, including:
/// - Root (`$`) and current (`@`) node references
/// - Child member access (`.name` or `['name']`)
/// - Array indexing (`[0]`) and slicing (`[1:3]`)
/// - Recursive descent (`..`) to search descendants
/// - Wildcards (`*`) to match any child
/// - Filter expressions (`?`) with comparisons and logical operators
/// - Function calls (`match(@, "[a-z]+")` or `count($.name)`)
///   - All standard JSONPath functions are supported
///   - Custom functions can be added via ``Path/Query/Function``
///
/// - SeeAlso:
///   - ``Value/subscript(path:delegate:)``
///   - [RFC-9535 JSONPath](https://tools.ietf.org/html/rfc9535)
///
public struct Path {

  /// Initial node identifier.
  public let initialNode: Identifier?

  /// Path segments.
  public let segments: [Segment]

  /// Initialize a path from a string.
  ///
  /// - Note: This initialize does not throw an error for invalid paths, returning `nil` instead.
  ///   For detailed errors, use ``Path/parse(_:)``.
  ///
  /// - Parameter path: The path string.
  public init?(path: String) {
    do {
      self = try Path.parse(string: path)
    } catch {
      return nil
    }
  }

  /// Initialize a path from an array of segments.
  ///
  /// - Parameter segments: The path segments.
  ///
  public init(segments: [Segment]) {
    self.initialNode = .root
    self.segments = segments
  }

  /// Internal initializer for creating special paths.
  ///
  /// - Parameters:
  ///   - initialNode: The initial node identifier.
  ///   - segments: The path segments.
  ///
  private init(initialNode: Identifier?, segments: [Segment]) {
    assert(initialNode == nil || segments.isEmpty, "initial node can only be nil if segments are empty.")
    self.initialNode = initialNode
    self.segments = segments
  }

  /// Initialize a path from a variadic list of segments.
  ///
  /// - Parameter segments: The path segments.
  public init(segments: Segment...) {
    self.init(segments: segments)
  }

  /// Append a child segment to the path.
  ///
  /// - Parameter name: The name of the child.
  /// - Returns: A new path with the child segment appended.
  public func appending(name: String) -> Path {
    appending(segment: .child([.name(name, quote: "'")]))
  }

  /// Append an index segment to the path.
  ///
  /// - Parameter index: The index of the child.
  /// - Returns: A new path with the index segment appended.
  public func appending(index: Int) -> Path {
    appending(segment: .child([.index(index)]))
  }

  /// Append a segment to the path.
  ///
  /// - Parameter segment: The segment to append.
  /// - Returns: A new path with the segment appended.
  public func appending(segment: Segment) -> Path {
    return Path(segments: segments + [segment])
  }

  /// Get the parent path.
  ///
  /// - Returns: A new path with the last segment removed, or the root path
  ///   if the path or parent path is empty.
  public var parent: Path {
    return Path(segments: Array(segments.dropLast()))
  }

  /// The root path.
  public static let root = Path(segments: [])

  /// Create a new root from the provided segments.
  ///
  /// - Parameter segments: The path segments.
  /// - Returns: A new path with the segments appended.
  public static func root(_ segments: [Path.Segment]) -> Path { Path(segments: segments) }

}

extension Path: Sendable {}

extension Path: Hashable {}

extension Path: Equatable {}

extension Path: CustomStringConvertible {

  /// A string representation of the path.
  ///
  /// This is a human-readable representation of the path, not necessarily a
  /// valid JSONPath string.
  public var description: String {
    if let initialNode {
      "\(initialNode.rawValue)\(segments.map(\.description).joined(separator: ""))"
    } else {
      "none"
    }
  }

}

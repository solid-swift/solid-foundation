# Media Type and HTTP Media Range Design

## Goal

SolidFoundation should provide an ergonomic Internet media type value that can replace the Sunday
`MediaType` concept without carrying over Sunday-specific API constraints. The API should separate
general media type syntax from HTTP `Accept` negotiation while integrating cleanly with Apple's
`swift-http-types` package.

## Module Placement

`MediaType` belongs in `SolidNet`.

Media types classify Internet representations and are useful outside HTTP, including JSON Schema
`contentMediaType`, serialization registries, and protocol metadata. `SolidNet` already hosts shared
Internet grammar types such as hostnames, email addresses, and IP addresses. Keeping `MediaType` in
`SolidNet` lets higher modules such as `SolidData`, `SolidSchema`, and a new `SolidHTTP` target reuse
the value without creating dependency cycles or pulling in HTTP-specific APIs.

HTTP-specific parsing and negotiation belong in a new `SolidHTTP` product and target.

`SolidHTTP` should depend on `SolidCore`, `SolidNet`, and Apple's `HTTPTypes` product. It should not
replace Apple's request, response, or header-field currency types. Instead, it should add typed
parsing, formatting, and negotiation helpers on top of `HTTPFields`.

## SolidNet.MediaType

`MediaType` is the canonical value for `type/subtype` strings and their parameters.

```swift
public struct MediaType: Equatable, Hashable, Sendable, Codable, LosslessStringConvertible {
  public let type: MediaType.Kind
  public let tree: MediaType.Tree
  public let subtype: String
  public let suffix: String?
  public let parameters: [String: String]

  public init?(string: String)
  public static func parse(_ string: String) throws -> MediaType
  public var serialized: String { get }
  public func matches(_ other: MediaType) -> Bool
}
```

The type should support:

- top-level kinds such as `application`, `text`, `image`, and wildcard `*`
- registration trees such as standard, vendor `vnd.`, personal `prs.`, unregistered `x.`, obsolete
  `x-`, and wildcard
- structured syntax suffixes stored as strings, so new suffix registrations do not require library
  changes
- lowercased canonical storage for type, tree, subtype, suffix, parameter names, and parameter values
- sorted canonical serialization for deterministic output
- single-value `Codable` using the canonical serialized form
- `LosslessStringConvertible` and `CustomStringConvertible`
- `Sendable`, `Equatable`, and `Hashable`

Common static constants should live on `MediaType`:

```swift
public static let json: MediaType
public static let cbor: MediaType
public static let html: MediaType
public static let plainText: MediaType
public static let eventStream: MediaType
public static let octetStream: MediaType
public static let formUrlEncoded: MediaType
public static let any: MediaType
public static let anyText: MediaType
public static let anyJSON: MediaType
```

Matching should be symmetric compatibility, not HTTP negotiation. Two media types match when their
non-wildcard type, tree, and subtype components agree, their suffixes are equal, and every parameter
name present on both sides has the same value.

## SolidHTTP.MediaRange

`MediaRange` represents one HTTP `Accept` media-range. It should not be used for `Content-Type`.

```swift
public struct MediaRange: Equatable, Hashable, Sendable {
  public let mediaType: MediaType
  public let quality: Double
  public let order: Int
  public let acceptExtensions: [String: String]
}
```

The `quality` value defaults to `1.0`. Values outside HTTP's valid `0...1` range must be rejected
as parse errors rather than silently normalized. `order` records the range position in the original
header value so ties can be resolved deterministically.

Accept extension parameters belong on `MediaRange`, not `MediaType`. Parameters before the `q`
separator are media type parameters. Parameters after `q` are accept extensions.

## SolidHTTP.MediaRanges

`MediaRanges` is the ordered collection and negotiation helper for `Accept`.

```swift
public struct MediaRanges: Equatable, Sendable, Collection {
  public static func parse(_ fieldValue: String) throws -> MediaRanges
  public func serialized() -> String
  public func bestMatch(in available: some Sequence<MediaType>) -> MediaType?
}
```

`bestMatch(in:)` should rank candidates by:

1. highest `q`
2. most specific media range
3. original header order
4. available type order

Specificity should prefer exact type/subtype over subtype wildcards, subtype wildcards over `*/*`,
and ranges with more media type parameters over ranges with fewer parameters when the parameters
match the available type.

Ranges with `q=0` are unacceptable and must not be selected.

## HTTPTypes Integration

`SolidHTTP` should add explicit helpers on `HTTPFields`:

```swift
extension HTTPFields {
  public mutating func setContentType(_ mediaType: MediaType)
  public func contentType() throws -> MediaType?
  public func requireContentType() throws -> MediaType

  public mutating func setAccept(_ ranges: MediaRanges)
  public func acceptMediaRanges() throws -> MediaRanges
}
```

Throwing reads keep malformed header behavior visible. Write helpers serialize through
`MediaType.serialized` and `MediaRanges.serialized()`.

`Content-Type` parsing must reject range-only syntax such as `q` metadata. `Accept` parsing must
interpret `q` as HTTP range quality metadata and not as a media type parameter.

## Parsing Strategy

The implementation should use a small tokenizer or hand-rolled parser rather than copying Sunday's
regular-expression implementation. This keeps behavior easier to audit against RFC 6838 and RFC
9110 and avoids adding a regex dependency.

Parsing should support reasonable HTTP whitespace around separators, but serialization should emit
compact canonical values:

```swift
application/problem+json;charset=utf-8
application/json,text/*;q=0.8,*/*;q=0.1
```

## Testing

Add focused tests in the fastest relevant targets first:

- `SolidNetTests` for `MediaType` parsing, serialization, matching, parameters, constants, Codable,
  and invalid input
- `SolidHTTPTests` for `MediaRange`, `MediaRanges`, `Accept` parsing, q-value ordering, `q=0`
  rejection during negotiation, content negotiation tie breaks, and `HTTPFields` integration

Run checks in this order:

1. `swift test --filter SolidNetTests`
2. `swift test --filter SolidHTTPTests`
3. `swift test`

Build warnings should be fixed as part of the implementation.

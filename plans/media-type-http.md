# MediaType and HTTP MediaRange Implementation Plan

This plan implements the approved design in
`docs/superpowers/specs/2026-05-14-media-type-design.md`.

## Goals

- Add a reusable `SolidNet.MediaType` value for Internet media types.
- Add curated `MediaType` constants broad enough for common API, document, archive, media, font,
  model, problem-details, and security use cases.
- Add a new `SolidHTTP` target for HTTP `Accept` media ranges and Apple `swift-http-types`
  integration.
- Keep general media type parsing independent of HTTP negotiation semantics.

## A. Package and Module Setup

1. Add Apple `swift-http-types` as a package dependency.
2. Add a `SolidHTTP` library product and target.
3. Make `SolidHTTP` depend on `SolidCore`, `SolidNet`, and `HTTPTypes`.
4. Add `SolidHTTPTests`.
5. Add `SolidHTTP` to the umbrella `Solid` target dependencies.
6. Add root re-export files for modules that should be available through `Solid`:
   - `Sources/Solid/Root/Net.swift`
   - `Sources/Solid/Root/HTTP.swift`
7. Update README/package module descriptions after the API shape is compiling.

## B. SolidNet.MediaType Core

Create focused files in `Sources/Solid/Net/`:

- `MediaType.swift`
- `MediaType-Parser.swift`
- `MediaType-Constants-API.swift`
- `MediaType-Constants-Documents.swift`
- `MediaType-Constants-Media.swift`
- `MediaType-Constants-Security.swift`

Implement `MediaType` as an immutable value:

```swift
public struct MediaType: Equatable, Hashable, Sendable, Codable, LosslessStringConvertible {
  public let type: MediaType.Kind
  public let tree: MediaType.Tree
  public let subtype: String
  public let suffix: String?
  public let parameters: [String: String]
}
```

Implementation details:

- Define `Kind` and `Tree` as nested public value types or enums, following what reads best once the
  parser constraints are clear.
- Store suffixes as strings, not a closed enum.
- Lowercase canonical fields and parameter names/values.
- Preserve obsolete tree serialization, such as `application/x-x509-ca-cert`.
- Sort parameters during serialization.
- Provide `init?(string:)`, `init(_:)`, `parse(_:) throws`, `serialized`, and `description`.
- Implement single-value `Codable`.
- Implement `matches(_:)` with symmetric wildcard/parameter compatibility.

Parsing should be hand-rolled or tokenizer-based, not regex-based. It should accept HTTP optional
whitespace around separators but serialize compactly.

## C. MediaType Constants

Add constants in themed extensions. Use the spec as the source of truth.

Coverage groups:

- API and structured data
- RFC 9457 and concise problem details
- Text and document types
- Archives and compression
- Images
- Audio
- Video
- Fonts
- Models and 3D assets
- Security material
- Wildcards and structured suffix wildcards

Use short names for clear common cases and longer names where needed:

```swift
MediaType.json
MediaType.problemJSON
MediaType.pkcs12
MediaType.pemCertificateChain
```

File-extension aliases are allowed when they improve call sites, even if two aliases serialize to
the same registered media type.

## D. SolidHTTP.MediaRange and MediaRanges

Create files in `Sources/Solid/HTTP/`:

- `MediaRange.swift`
- `MediaRanges.swift`
- `MediaRanges-Parser.swift`
- `HTTPFields+MediaTypes.swift`

Implement one `Accept` range:

```swift
public struct MediaRange: Equatable, Hashable, Sendable {
  public let mediaType: MediaType
  public let quality: Double
  public let order: Int
  public let acceptExtensions: [String: String]
}
```

Rules:

- Default `quality` is `1.0`.
- Reject q-values outside `0...1`.
- Keep `q=0` ranges in parsed output, but never select them during negotiation.
- Parameters before `q` belong to the media type.
- Parameters after `q` are `acceptExtensions`.

Implement `MediaRanges` as an ordered collection with:

- `parse(_:) throws`
- `serialized`
- `bestMatch(in:)`

Selection order:

1. highest quality
2. most specific range
3. original header order
4. available media type order

Specificity prefers exact type/subtype, then subtype wildcards, then `*/*`, and uses matching
parameter count as an additional tiebreaker.

## E. HTTPTypes Integration

Add explicit extensions on `HTTPFields`:

```swift
extension HTTPFields {
  public mutating func setContentType(_ mediaType: MediaType)
  public func contentType() throws -> MediaType?
  public func requireContentType() throws -> MediaType

  public mutating func setAccept(_ ranges: MediaRanges)
  public func acceptMediaRanges() throws -> MediaRanges
}
```

Read APIs throw so malformed headers are visible. Write APIs serialize through `MediaType` and
`MediaRanges`.

`Content-Type` must reject `Accept`-only range metadata such as `q`. `Accept` parsing must treat `q`
as range metadata rather than a media type parameter.

## F. Tests

Use Swift Testing for new suites.

`SolidNetTests`:

- valid and invalid `MediaType` parsing
- canonical lowercasing and serialization
- tree parsing and serialization
- suffix parsing and structured suffix wildcard matching
- parameter parsing, lookup, serialization order, and compatibility
- `Codable` round trips
- representative constants from every extension group
- obsolete X.509 serialization

`SolidHTTPTests`:

- single media range parsing
- comma-separated `Accept` parsing
- q-value defaults, ordering, rejection, and `q=0` negotiation behavior
- accept extensions after `q`
- best-match ordering by q, specificity, header order, and available order
- `HTTPFields` content type helpers
- `HTTPFields` accept helpers
- malformed field behavior

## Verification Order

Run checks from fastest to broadest:

1. `swift test --filter SolidNetTests`
2. `swift test --filter SolidHTTPTests`
3. `swift test`

Fix build warnings as part of the implementation.

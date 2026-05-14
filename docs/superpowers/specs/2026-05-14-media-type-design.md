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

Common static constants should live on `MediaType` and are detailed in the extension set below.

Matching should be symmetric compatibility, not HTTP negotiation. Two media types match when their
non-wildcard type, tree, and subtype components agree, their suffixes are equal, and every parameter
name present on both sides has the same value.

## MediaType Extension Sets

`MediaType` should ship with curated static constants for common API, document, media, problem, and
security formats. These should be implemented as focused extensions in separate files, not as one
large registry type. The goal is ergonomic coverage for real application code, not a full mirror of
the IANA media type registry.

Use short names for unambiguous everyday types and longer names when the shorter form would be
unclear:

```swift
MediaType.json
MediaType.problemJSON
MediaType.pkcs12
MediaType.pemCertificateChain
```

The initial extension set should include:

```swift
// API and structured data
public static let json: MediaType
public static let cbor: MediaType
public static let cborSequence: MediaType
public static let xml: MediaType
public static let yaml: MediaType
public static let ndjson: MediaType
public static let jsonPatch: MediaType
public static let mergePatchJSON: MediaType
public static let formUrlEncoded: MediaType
public static let multipartFormData: MediaType
public static let graphql: MediaType
public static let graphqlResponseJSON: MediaType
public static let senmlCBOR: MediaType
public static let sensmlCBOR: MediaType
public static let senmlEtchCBOR: MediaType

// RFC 9457 Problem Details
public static let problemJSON: MediaType
public static let problemXML: MediaType
public static let conciseProblemCBOR: MediaType

// Text and documents
public static let plainText: MediaType
public static let html: MediaType
public static let css: MediaType
public static let csv: MediaType
public static let markdown: MediaType
public static let javascript: MediaType
public static let pdf: MediaType
public static let zip: MediaType
public static let gzip: MediaType
public static let octetStream: MediaType

// Images
public static let png: MediaType
public static let jpeg: MediaType
public static let gif: MediaType
public static let webp: MediaType
public static let avif: MediaType
public static let svg: MediaType
public static let tiff: MediaType
public static let icon: MediaType

// Video
public static let mp4: MediaType
public static let mpegVideo: MediaType
public static let quickTime: MediaType
public static let webmVideo: MediaType

// Security material: certificates, keys, signatures, and bundles
public static let jose: MediaType
public static let joseJSON: MediaType
public static let jwt: MediaType
public static let jwkJSON: MediaType
public static let jwkSetJSON: MediaType
public static let cms: MediaType
public static let cose: MediaType
public static let coseKey: MediaType
public static let coseKeySet: MediaType
public static let coseX509: MediaType
public static let cwt: MediaType
public static let pemCertificateChain: MediaType
public static let pkixCertificate: MediaType
public static let pkixAttributeCertificate: MediaType
public static let pkixCertificateRevocationList: MediaType
public static let pkixCertificationPath: MediaType
public static let pkcs7Mime: MediaType
public static let pkcs7Signature: MediaType
public static let pkcs10: MediaType
public static let pkcs8: MediaType
public static let pkcs8Encrypted: MediaType
public static let pkcs12: MediaType
public static let pgpKeys: MediaType
public static let pgpSignature: MediaType
public static let pgpEncrypted: MediaType
public static let x509CACertificate: MediaType
public static let x509UserCertificate: MediaType

// Wildcards and structured suffix matching
public static let any: MediaType
public static let anyText: MediaType
public static let anyImage: MediaType
public static let anyVideo: MediaType
public static let anyJSON: MediaType
public static let anyXML: MediaType
public static let anyCBOR: MediaType
public static let anyCBORSequence: MediaType
```

Constants that represent registered obsolete or `x-` types should preserve their registered spelling
in serialization but use modern Swift names. For example, `x509CACertificate` should serialize as
`application/x-x509-ca-cert`.

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

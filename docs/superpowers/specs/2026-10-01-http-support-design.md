# HTTP Support: Problem Details, Server-Sent Events, Multipart, Typed Fields

Part of the [SolidCoding design set](2026-09-30-solid-coding-design.md).

## Goal

`SolidHTTP` should provide complete, standards-based implementations of the HTTP-level pieces a REST
client or server runtime needs. They build on Apple's swift-http-types (`HTTPRequest`,
`HTTPResponse`, `HTTPFields`) and do not replace it. Each piece has a transport-agnostic core over
SolidIO `Source`/`Sink`. That keeps it usable by Sunday's URLSession transport, a Linux
AsyncHTTPClient transport, and server frameworks.

| Area | Standard |
| --- | --- |
| Field syntax toolkit | [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) §5.5–5.6 |
| Typed fields | RFC 9110 sections per field; [RFC 6750](https://www.rfc-editor.org/rfc/rfc6750), [RFC 8288](https://www.rfc-editor.org/rfc/rfc8288), [RFC 6266](https://www.rfc-editor.org/rfc/rfc6266), [RFC 8187](https://www.rfc-editor.org/rfc/rfc8187) |
| Problem Details | [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457) (JSON); [RFC 9290](https://www.rfc-editor.org/rfc/rfc9290) (CBOR) |
| Server-Sent Events | [WHATWG HTML §9.2](https://html.spec.whatwg.org/multipage/server-sent-events.html) |
| Multipart | [RFC 2046](https://www.rfc-editor.org/rfc/rfc2046) §5.1, [RFC 7578](https://www.rfc-editor.org/rfc/rfc7578), [RFC 2387](https://www.rfc-editor.org/rfc/rfc2387) |
| Text bodies | RFC 9110 §8.3, [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259) §8.1 |

`MediaType` and `MediaRanges` (Accept negotiation) already exist and are not repeated here.

## Field Syntax Toolkit

A small parser/serializer for the RFC 9110 §5.6 common rules. Every typed field is built on it, so
quoting and lists behave the same everywhere:

- `token`, `quoted-string` (with `quoted-pair`), `comment`, `parameters` (`;` name `=` value), and
  `#rule` lists with empty elements tolerated on receipt (§5.6.1)
- `OWS`/`RWS`/`BWS` whitespace rules, case-insensitive names, and serialization that quotes only
  when required
- `HTTPFields` helpers: `values(for:)` joins repeated field lines with `,`. `Set-Cookie` is never
  joined (RFC 9110 §5.3).

## Typed Fields

Each field has a value type with `parse(_:) throws` and `serialized`, plus `HTTPFields` accessors.
Each implements the field's full grammar, not just the common case.

| Field | Type | Standard |
| --- | --- | --- |
| `Content-Type`, `Accept` | `MediaType`, `MediaRanges` | exist |
| `Accept-Language`, `Content-Language` | `LanguageRanges`, `[LanguageTag]` | RFC 9110 §12.5.4, §8.5; [RFC 4647](https://www.rfc-editor.org/rfc/rfc4647) matching |
| `Authorization`, `Proxy-Authorization` | `Credentials` (scheme + token68 or auth-params); `.bearer(String)` | RFC 9110 §11.4; RFC 6750 §2.1 |
| `WWW-Authenticate` | `[Challenge]` | RFC 9110 §11.6.1 (multiple challenges per line, comma ambiguity handled by the grammar) |
| `Retry-After` | `.date(Instant)` / `.delay(Duration)` | RFC 9110 §10.2.3 |
| `Date`, `Last-Modified`, `If-Modified-Since`, `If-Unmodified-Since`, `Expires` | `Instant` via HTTP-date | RFC 9110 §5.6.7 (see the [Tempo formats design](2026-10-01-tempo-formats-design.md)) |
| `ETag`, `If-Match`, `If-None-Match` | `EntityTag` (strong/weak), `.any` | RFC 9110 §8.8.3, §13.1.1–13.1.2, with strong and weak comparison |
| `Link` | `[LinkValue]` (target `URI`, `rel` set, params, `title*`) | RFC 8288 §3 (with RFC 8187 extended values) |
| `Content-Disposition` | `ContentDisposition` (type, `filename`, `filename*`, params) | RFC 6266 + RFC 8187 |
| `Location`, `Content-Location` | `URI` (reference, resolved against the request URI) | RFC 9110 §10.2.2, §8.7 |
| `Last-Event-ID` | `String` | WHATWG HTML §9.2 |

Fields are added when a consumer needs them. Each addition must come with its complete grammar and
the RFC's examples as tests.

## Problem Details (RFC 9457)

```swift
public struct Problem: Error, Sendable, Hashable {
  public var type: URI                       // default "about:blank"
  public var title: String?
  public var status: HTTPResponse.Status?
  public var detail: String?
  public var instance: URI?
  public var extensions: Value.Object        // ordered; unknown members preserved losslessly

  public init(type: URI = .aboutBlank, title: String? = nil, status: HTTPResponse.Status? = nil,
              detail: String? = nil, instance: URI? = nil, extensions: Value.Object = [:])
  public static func status(_ status: HTTPResponse.Status, detail: String? = nil) -> Problem   // about:blank + reason phrase
}

public protocol ProblemType: Error, SchemaCodable, Sendable {
  static var type: URI { get }
  static var title: String { get }
  static var status: HTTPResponse.Status? { get }
  var problem: Problem { get }               // generic view, for logging and rethrowing
}
```

### Conformance

- **Member types.** A member whose JSON type is wrong **is ignored** (§3.1), not rejected: a numeric
  `title` is treated as absent. The decoder implements this rule directly. It is the one place
  where the schema-driven reader runs in "ignore mismatched member" mode.
- **`type` and `instance`** are URI references. Relative references are resolved against the
  response's base URI (§3.1). Decoding takes an optional `baseURI`.
- **`status` is advisory** (§3.1.2). Consumers get both the HTTP status and the member, and the API
  says which is authoritative. A mismatch is reported through a warning hook, not an error.
- **`about:blank`.** Its `title` should be the status reason phrase (§4.2.1). `Problem.status(_:)`
  does this.
- **Extension member names.** §3.2 recommends names that are XML-compatible (letter first;
  `ALPHA`/`DIGIT`/`_`; at least three characters). Encoding validates this in debug builds.

### Representations

| Media type | Support |
| --- | --- |
| `application/problem+json` | Full |
| `application/concise-problem-details+cbor` (RFC 9290) | Full. RFC 9290 uses integer keys for standard members and defines custom-entry rules. The RFC 9457 ↔ RFC 9290 member mapping is specified in code and tested against RFC 9290's examples. |
| `application/problem+xml` (RFC 9457 Appendix B) | Deferred to the planned SolidXML format. Until then, encoding or decoding it throws `unsupportedRepresentation`; it is never half-done. Current Solid servers produce JSON problems only. Once SolidXML exists, Appendix B's mapping (namespace `urn:ietf:rfc:7807`, extension members as elements) becomes a `representations` entry for the `xml` format. |

Content-type matching uses `MediaType.matches`, so `application/problem+json; charset=utf-8` works.
Sunday's `==` check misses that case today.

### Typed problems and registry

```swift
@ProblemType(type: "https://example.com/probs/out-of-credit",
             title: "You do not have enough credit.", status: .forbidden)
public struct OutOfCredit {
  public var balance: Int
  public var accounts: [URI]
}

let registry = ProblemRegistry([OutOfCredit.self, RateLimited.self])
let error: any Error = try registry.decode(response: response, body: body)  // typed if registered, else Problem
let response = HTTPResponse(problem: OutOfCredit(balance: 30, accounts: [...]), language: "en")
```

- `@ProblemType` is a `SolidCoding` macro. Typed extension members are fields. Unknown members go to
  `extensions`.
- On the server, `HTTPResponse(problem:)` sets the status, `Content-Type`, and optionally
  `Content-Language`.

## Server-Sent Events (WHATWG HTML §9.2)

### Parser

```swift
public struct ServerSentEvent: Sendable, Hashable {
  public var type: String                    // "message" when no event field
  public var data: String
  public var lastEventID: String             // value of the last-event-ID buffer at dispatch
  public var retry: Duration?                // reconnection time set by this event's block, if any
  public var extensionFields: [(name: String, value: String)]   // only when requested
}

public struct SSEParser: Sendable {
  public init(options: Options = .default)  // .preserveUnknownFields, .preserveComments
  public mutating func feed(_ bytes: some Sequence<UInt8>, isFinal: Bool) -> [ServerSentEvent]
}

extension SSE {
  public static func events(from source: some Source) -> AsyncThrowingStream<ServerSentEvent, Error>
  public static func decode<T: SchemaDecodable>(_: T.Type, from source: some Source,
                                                 format: some CodingFormat = .json)
    -> AsyncThrowingStream<TypedEvent<T>, Error>
}
```

It implements "interpreting an event stream" exactly:
- **Decoding:** UTF-8 decode with replacement, and a leading BOM stripped. Lines end at CRLF, LF, or
  CR, including a CR at the end of one chunk followed by an LF at the start of the next.
- **Field lines:**
  - A line starting with `:` is a comment.
  - `field:value`, with one leading space removed from the value. A line with no colon is a field
    with an empty value.
  - `data` appends the value plus LF to the data buffer.
  - `event` sets the type buffer.
  - `id` sets the last-event-ID buffer, unless the value contains NUL.
  - `retry` takes effect only if the value is all ASCII digits.
  - Unknown fields are ignored, or surfaced as `extensionFields` when requested. Sunday's
    `retry-max` and `keepalive` use this.
- **Dispatch on a blank line:**
  - An empty data buffer means no event; the type buffer is reset either way.
  - One trailing LF is removed from the data.
  - The type defaults to `message`.
  - The last-event-ID buffer persists across events.
- **End of stream:** an incomplete final event is discarded.

### Writer

```swift
public struct SSEWriter: Sendable {
  public func serialize(_ event: OutgoingEvent) throws(SSEError) -> [UInt8]
  public func comment(_ text: String) -> [UInt8]          // heartbeats
}
```

- `data` is split on any line ending into multiple `data:` lines.
- `event` and `id` with CR/LF, or an `id` containing NUL, are errors.
- `retry` is written in milliseconds.
- Output always uses LF line endings and ends each event with a blank line.

### Connection state machine

`EventSourceSession` implements the §9.2.3 processing model without doing any I/O. A transport
drives it:

```swift
public struct EventSourceSession: Sendable {
  public enum ReadyState: Sendable { case connecting, open, closed }
  public enum Action: Sendable {
    case connect(HTTPRequest)                         // includes Accept and Last-Event-ID
    case deliver([ServerSentEvent])
    case reconnect(after: Duration)
    case fail(EventSourceFailure)                     // no further reconnection
  }

  public init(url: URI, policy: ReconnectionPolicy = .default)
  public mutating func responseReceived(_ response: HTTPResponse) -> Action
  public mutating func bytesReceived(_ bytes: some Sequence<UInt8>) -> Action
  public mutating func connectionEnded(error: (any Error)?) -> Action
  public mutating func close()
}
```

- **Fail, no retry:** a status other than 200, or a `Content-Type` other than `text/event-stream`,
  fails the connection.
- **Retry:** a network error or a clean end of stream schedules reconnection after the current
  reconnection time.
- **`Last-Event-ID`** is sent when the buffer is non-empty.
- **`ReconnectionPolicy`** adds the backoff and jitter the spec permits. Sunday's capped
  exponential backoff and keepalive watchdog become policy, not parser behaviour.

## Multipart (RFC 2046 §5.1, RFC 7578, RFC 2387)

Sunday has no multipart support today. OpenAPI request bodies routinely use `multipart/form-data`
(with the `encoding` object), so it is part of this scope.

```swift
public struct MultipartReader: ~Copyable {
  public init(source: some Source, boundary: String, limits: Limits = .default) throws(MultipartError)
  public mutating func nextPart() async throws(MultipartError) -> MultipartPart?   // streaming; body is a Source
}

public struct MultipartWriter: ~Copyable {
  public init(sink: some Sink, subtype: String = "form-data", boundary: String = .randomBoundary())
  public mutating func writePart(headers: HTTPFields, body: some Source) async throws
  public mutating func finish() async throws
}

public struct MultipartFormData: Sendable {                    // ergonomic builder
  public mutating func append(_ name: String, _ value: String)
  public mutating func append(_ name: String, file: some Source, filename: String, contentType: MediaType)
  public mutating func append<T: SchemaEncodable>(_ name: String, _ value: T, as format: some CodingFormat)
}
```

- **Grammar.**
  - Boundaries are 1–70 characters from `bchars` and must not end in a space. The writer generates
    a cryptographically random boundary.
  - Preamble and epilogue are ignored.
  - Delimiters are `CRLF--boundary`, and transport padding after a delimiter is accepted.
  - Part headers use RFC 5322 field syntax; obsolete line folding is rejected.
- **`multipart/form-data` (RFC 7578).**
  - Every part has `Content-Disposition: form-data; name=…`, plus `filename` for files.
  - Parts default to `text/plain`.
  - The `_charset_` field is honoured.
  - `filename*` is never generated (§4.2).
  - Senders never generate `Content-Transfer-Encoding` (§4.7). Readers accept `7bit`/`8bit`/`binary`
    and, with `Limits.decodeTransferEncodings`, decode `base64`/`quoted-printable` using the
    existing SolidCore codecs.
- **Schema mapping.** An object schema maps to parts. Each property's part content type comes from
  the OpenAPI `encoding` object, which the generator carries into the plan; the default is
  `text/plain` for scalars and `application/json` for objects. The reader decodes each part with
  the right `CodingFormat`.
- **`multipart/mixed`, `multipart/related`.** Supported by the same reader and writer. `related`
  honours the `start` and `type` parameters (RFC 2387).
- **Limits.** Part count, header size, and per-part body size, for servers.

## Text Bodies and Charsets

- `application/json` is always UTF-8 (RFC 8259 §8.1). A `charset` parameter is ignored.
- `text/*` uses the `charset` parameter. Supported: UTF-8, UTF-16 (BOM-detected or explicit
  LE/BE), US-ASCII, and ISO-8859-1. Any other charset fails with `unsupportedCharset`; there is no
  silent fallback.
- When a `text/*` type has no `charset`, UTF-8 is assumed. RFC 9110 removed the old ISO-8859-1
  default.

## Testing

- Each typed field: the RFC's ABNF edge cases and every example in its RFC.
- Problem Details: RFC 9457 §3 and Appendix examples, and RFC 9290 examples. Mismatched member
  types are ignored.
- SSE: port the WPT `eventsource/format-*` cases plus the spec's examples. Chunk-boundary fuzzing:
  feed every split point of each fixture.
- Multipart: RFC 2046 and RFC 7578 examples, plus boundary-in-body adversarial cases, limits, and
  chunk-boundary fuzzing.

## Open Questions

1. Should `SolidHTTP` adopt [RFC 9651](https://www.rfc-editor.org/rfc/rfc9651) Structured Fields
   now, for future fields, or wait until a needed field requires it?

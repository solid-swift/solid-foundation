# Percent-Encoding, Form Encoding, and Parameter Serialization

Part of the [SolidCoding design set](2026-09-30-solid-coding-design.md).

## Goal

Complete, standards-based implementations of every URL-level encoding a REST client or server
needs. Each comes with an ergonomic API and a conformance test corpus:

| Area | Standard | Module |
| --- | --- | --- |
| Percent-encoding | [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986) §2, §3; [RFC 3987](https://www.rfc-editor.org/rfc/rfc3987) §3.1; [WHATWG URL](https://url.spec.whatwg.org/) percent-encode sets | `SolidURI` |
| `application/x-www-form-urlencoded` | [WHATWG URL §5](https://url.spec.whatwg.org/#application/x-www-form-urlencoded) | `SolidURI` (tuples), `SolidCoding` (structured format) |
| Structured form conventions | No RFC; named de facto conventions (below) | `SolidCoding` |
| URI Templates | [RFC 6570](https://www.rfc-editor.org/rfc/rfc6570) (implemented; additions below) | `SolidURI` |
| Parameter serialization | [OpenAPI 3.1 §4.8.12.4](https://spec.openapis.org/oas/v3.1.1.html#style-values) style values on RFC 6570 | `SolidCoding` |
| Cookies (parameter location) | [RFC 6265](https://www.rfc-editor.org/rfc/rfc6265) §4.2 `cookie-string` | `SolidHTTP` |

## Percent-Encoding

There is no public percent-encoding API today. `URI.QueryItem` uses Foundation's
`.urlQueryAllowed`, which leaves `&`, `=`, `+`, and `?` unescaped inside names and values.

```swift
extension URI {
  public enum PercentEncoding {
    public static func encode(_ string: some StringProtocol, allowing set: CharacterSet) -> String
    public static func encode(_ bytes: some Sequence<UInt8>, allowing set: CharacterSet) -> String
    public static func decode(_ string: some StringProtocol, mode: DecodeMode = .strict) throws(PercentDecodingError) -> String
    public static func decodeBytes(_ string: some StringProtocol, mode: DecodeMode = .strict) throws(PercentDecodingError) -> [UInt8]

    public enum DecodeMode: Sendable {
      case strict          // malformed "%" sequences and invalid UTF-8 are errors
      case lenient         // WHATWG: malformed "%" left as-is, invalid UTF-8 replaced with U+FFFD
    }

    public struct CharacterSet: Sendable {          // ASCII bitmap, no Foundation dependency
      // RFC 3986 component sets (from the ABNF)
      public static let unreserved, pathSegment, pathSegmentNoColon, query, fragment, userinfo, regName: Self
      // RFC 6570 expansion sets
      public static let templateUnreserved, templateReserved: Self
      // WHATWG URL percent-encode sets (complements; listed by spec name)
      public static let c0Control, whatwgFragment, whatwgQuery, whatwgSpecialQuery, whatwgPath,
                        whatwgUserinfo, whatwgComponent, formURLEncoded: Self
      public func union(_ other: Self) -> Self
      public func subtracting(_ other: Self) -> Self
    }
  }
}
```

- Encoding is UTF-8, with uppercase hex as RFC 3986 §2.1 recommends. Output never contains a `%`
  that is not part of a triplet.
- **Normalization** follows RFC 3986 §6.2.2:
  - `URI.normalized()` uses it.
  - Percent-encoded unreserved octets are decoded, and hex digits are uppercased.
  - Reserved octets are never decoded.
- **IRI ↔ URI mapping**: `URI.iriToURI()` and `URI.uriToDisplayIRI()`, per RFC 3987 §3.1–3.2.
- `URI.QueryItem.encoded` is re-implemented on `.query` minus `&`, `=`, `+`, `#`. This fixes the
  current bug.

## `application/x-www-form-urlencoded`

### Tuple layer (WHATWG URL §5, exact)

```swift
public struct FormFields: Sendable, Hashable, RandomAccessCollection, ExpressibleByDictionaryLiteral {
  public init()
  public init(parsing bytes: some Sequence<UInt8>)              // §5.1 parser
  public init(parsing string: some StringProtocol)
  public var serialized: String { get }                          // §5.2 serializer

  // URLSearchParams-shaped API (familiar from the web platform)
  public mutating func append(_ name: String, _ value: String)
  public mutating func set(_ name: String, _ value: String)     // replaces the first, removes the rest
  public mutating func remove(_ name: String, value: String? = nil)
  public func first(_ name: String) -> String?
  public func all(_ name: String) -> [String]
  public func contains(_ name: String, value: String? = nil) -> Bool
  public mutating func sort()                                    // stable, by UTF-16 code units, per spec

  public subscript(position: Int) -> (name: String, value: String) { get }
}
```

- **Parser:**
  - Splits on `&` and skips empty sequences.
  - Splits each sequence on the first `=`.
  - Replaces `+` with space.
  - Percent-decodes in lenient mode, then decodes UTF-8 without BOM, replacing invalid bytes.
- **Serializer:**
  - Encodes as UTF-8.
  - Uses the spec's `application/x-www-form-urlencoded` percent-encode set.
  - Uses `+` for space.
  - Joins with `=` and `&`.
- **Charsets.** Only UTF-8 is supported, as the spec recommends. Legacy encodings and the
  `_charset_` field are not supported. Encountering `_charset_` is not an error; it is just a field.

### Structured layer (a `SolidCoding` format)

Forms carry only string tuples. Nesting and arrays are conventions. Each is implemented completely
and named explicitly. No default guesses at the server's convention.

| `FormStructure` | Arrays | Objects | Example |
| --- | --- | --- | --- |
| `.flat` | repeated key | not allowed (error) | `tag=a&tag=b` |
| `.brackets` (Rack / PHP) | `key[]` | `key[sub]` | `tags[]=a&owner[name]=x` |
| `.indexedBrackets` | `key[0]` | `key[sub]` | `tags[0]=a&owner[name]=x` |
| `.dotted` (Spring) | repeated key, or `key[0]` | `key.sub` | `owner.name=x` |
| `.deepObject` (OpenAPI) | not allowed (error) | `key[sub]`, one level | `filter[color]=red` |

- **Writer.** `FormFormat` implements `FormatEventWriter`. Objects and arrays are flattened by the
  chosen convention. Scalars are written as text in the representation the field's coding plan
  chooses (dates per `format`/`units`, bytes per `encoding`). `null` follows `FormOptions.nulls`:
  `.omit` (default), `.emptyValue` (`key=`), or `.bareKey` (`key`).
- **Reader.** `FormFormat` also implements `FormatEventReader`. It rebuilds the structure from the
  convention:
  - Conflicts are errors, not silent overwrites: `a=1&a[b]=2` is an error, and so is
    `tags[0]=x&tags[2]=y` with a gap.
  - All scalars arrive as strings. The schema-driven reader coerces them to the planned type with
    text-to-number, text-to-bool, and text-to-date parsing. That is only possible because the
    representation comes from the schema.
- **Booleans.** `FormOptions.booleans` is `.literal` (`true`/`false`, the default) or `.numeric`
  (`1`/`0`). The reader also accepts HTML checkbox `on` when `.acceptCheckboxOn` is set.
- **Entry points:**
  - `Form.encode(value, structure:) -> String`
  - `Form.decode(T.self, from:, structure:)`
  - `FormFields` interop through `Form.encode(value, structure:) -> FormFields`

## URI Template Additions (RFC 6570)

`URI.Template` already implements levels 1–4. Additions:

- **Ordered associative values.** `Template.Value.assoc` changes from `[String: String?]` to an
  ordered list of `(String, String?)` pairs. Today explode order is random. This is a source-breaking
  change; keep the `Dictionary` init for convenience.
- **`URITemplateValue` protocol** for ergonomic expansion arguments:
  - `String`, `Int` family, `Bool`, `UUID`, `URI`, arrays, `KeyValuePairs`, and `OrderedDictionary`
    conform.
  - `SchemaEncodable` values convert through the parameter serializer below.
  - `template.expand(["id": petID, "tags": tags])`.
- **Undefined vs. empty** values per §2.3. `nil`, empty lists, and empty assoc values are undefined
  and omitted, which differs from the empty string. Add explicit tests.
- **Conformance corpus.** Vendor [uritemplate-test](https://github.com/uri-templates/uritemplate-test)
  (`spec-examples.json`, `spec-examples-by-section.json`, `extended-tests.json`,
  `negative-tests.json`) and run it.
- **Matching** (template → variables), for servers and routing. RFC 6570 §1.5 says matching is
  ambiguous in general. Support the unambiguous subset: level 1–3 expressions separated by literals,
  with `/`-segment and `;`/`?`/`&` operators. Report ambiguity at template parse time. This replaces
  the regex-based route matcher in Sunday's test server.

## Parameter Serialization (OpenAPI 3.1 styles)

Sunday generates from OpenAPI and RAML, so parameter serialization implements the OpenAPI style
table completely, on top of RFC 6570 where an operator exists.

| Location | `style` | `explode: false` | `explode: true` | Implementation |
| --- | --- | --- | --- | --- |
| path | `simple` (default) | `{id}` | `{id*}` | RFC 6570 simple |
| path | `label` | `{.id}` | `{.id*}` | RFC 6570 `.` |
| path | `matrix` | `{;id}` | `{;id*}` | RFC 6570 `;` |
| query | `form` (default) | `{?id}` | `{?id*}` | RFC 6570 `?` / `&` |
| query | `spaceDelimited` | `id=a%20b` | n/a (as `form`) | custom |
| query | `pipeDelimited` | `id=a\|b` | n/a (as `form`) | custom |
| query | `deepObject` | n/a | `id[k]=v` | custom (`FormStructure.deepObject`) |
| header | `simple` | `a,b` / `k,v` | `k=v` | RFC 6570 simple, unencoded |
| cookie | `form` | `id=a,b` | `id=a; id=b` | RFC 6265 `cookie-string` (OpenAPI 3.1 leaves exploded cookies underspecified; this follows the 3.2 `cookie` style) |

```swift
public struct ParameterSerializer: Sendable {
  public init(location: ParameterLocation, style: ParameterStyle? = nil, explode: Bool? = nil,
              allowReserved: Bool = false, allowEmptyValue: Bool = false)
  public func serialize<T: SchemaEncodable>(name: String, _ value: T) throws(CodingError) -> SerializedParameter
  public func serialize(name: String, _ value: Value, plan: Schema.CodingPlan.Node) throws(CodingError) -> SerializedParameter
  public func parse(name: String, from raw: SerializedParameter, plan: Schema.CodingPlan.Node) throws(CodingError) -> Value
}
```

- Defaults per location follow OpenAPI: path → `simple`; query and cookie → `form` with
  `explode: true`; header → `simple`.
- `allowReserved` maps to RFC 6570 `+` behaviour for query values.
- **Scalars** are stringified from the coding plan. A `date-time` stored as epoch milliseconds
  serializes as that number; one stored as RFC 3339 serializes as that string.
- **`parse`** is the server-side inverse. Values are typed by the plan, and ambiguous forms are
  rejected (for example `explode: false` objects whose values contain `,`).
- **RAML** query parameters map to `form`/`explode: true`. RAML URI parameters map to `simple`.
- **OpenAPI 3.2** adds the `querystring` location and a `cookie` style. The table above is the 3.1
  baseline. Add 3.2 when the generator supports it.

## Testing

- WHATWG [web-platform-tests](https://github.com/web-platform-tests/wpt) `url/urlencoded-parser.any.js`
  and `url/urlsearchparams-*.any.js`, ported as data-driven Swift tests.
- `uritemplate-test` corpus (above).
- The OpenAPI specification's style examples table as fixtures. Every row round-trips:
  serialize, then parse, gives the same value.
- RFC 3986 §5.4 reference-resolution examples (normal and abnormal) for `URI.resolved(against:)`,
  if not already covered.

## Open Questions

1. Should `FormFields` keep the WHATWG name `URLSearchParams` for familiarity?
2. Should `.dotted` arrays default to repeated keys or indexed keys? Spring accepts both; emitting
   indexed keys is the safer round trip.

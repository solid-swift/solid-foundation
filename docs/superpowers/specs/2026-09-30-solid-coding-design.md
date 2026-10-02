# SolidCoding Design

## Goal

SolidFoundation should provide a schema-driven, event-based replacement for Swift `Codable` in a new
`SolidCoding` module. It must be fast, stream-friendly, and lossless, and it must be easy to write
by hand and easy to generate. It is the main missing piece that keeps the Sunday Swift runtime
(`sunday-swift`) and Sunday's generated code from depending only on SolidFoundation.

The JSON Schema, extended with a Solid coding vocabulary, is the only place that decides how data
is represented on the wire and how it is validated. Swift type code describes structure only:
which properties exist and what Swift types they have. Every `SolidCoding` type is also `Codable`,
so it works with any `Codable`-based API. The representation still comes from the schema.

## Design Set

| Document | Scope |
| --- | --- |
| This document | `SolidCoding`: reader/writer, codecs, Codable integration, vocabulary, macros, entry points |
| [Schema streaming evaluation and coding plans](2026-10-01-schema-streaming-evaluation-design.md) | `SolidSchema`: event-driven evaluator, coding plans, codability analysis, type binding, schema-only `Value` coder |
| [JSON Patch and JSON Merge Patch](2026-10-01-json-patch-design.md) | `SolidData` RFC 6902/7396; typed `PatchOp`/`UpdateOp`/`MergeOp`, generated patch types, typed patch builder |
| [Percent-encoding, form encoding, parameter serialization](2026-10-01-url-form-encoding-design.md) | RFC 3986/3987 percent-encoding, WHATWG `x-www-form-urlencoded`, structured forms, RFC 6570 additions, OpenAPI parameter styles |
| [HTTP support](2026-10-01-http-support-design.md) | Typed fields, Problem Details (RFC 9457/9290), Server-Sent Events, multipart, text charsets |
| [Tempo wire formats](2026-10-01-tempo-formats-design.md) | RFC 3339, RFC 9557, ISO 8601 durations, HTTP-date, epoch units, CBOR date tags |
| [Format-targeted representations and tags](2026-10-01-representations-and-tags-design.md) | `representations` overrides (all / text / binary / one format), `FormatID`, typed `Tag`/`TagType`/`TagRegistry`, tag validation and policy |
| SolidXML (planned, not yet written) | Hand-written XML format with the same event reader/writer and streaming support as JSON, YAML, and CBOR; prerequisite for `application/problem+xml` |

## Background

### Why not `Codable` as the engine

- **Free-form data is lossy.** `[String: Any]` and similar have no faithful round trip. Key order,
  number precision, tags, and the integer/float distinction are lost.
- **New formats are hard to add.** Each format needs a full `Encoder`/`Decoder` container stack.
- **It is slow.** Containers are reference types, every level allocates, and dispatch goes through
  existentials and dynamic casts.
- **It cannot stream.** `Decoder` needs a random-access tree.
- **Validation is a separate pass**, and representation is decided by encoder-wide strategies, not
  per field.

`Codable` remains the **interop surface** ([Codable integration](#codable-integration)). It is not
the engine.

### What Sunday needs

| Dependency | Used for |
| --- | --- |
| PotentCodables `AnyValue`, `AnyValueEncoder`/`Decoder`, `AnyCodingKey` | Free-form fields, preserved unknown properties, `Problem.parameters`, parameter/form encoding |
| PotentJSON / PotentCBOR | Body coders (epoch-seconds dates; JSON from `Data` or `String`; CBOR tagged and untagged dates) |
| sharplet/Regex | Media type parsing; test-server routing |
| SwiftScream URITemplate | Path and base-URL template expansion |
| BigInt, Float16, swift-numerics, PotentYAML, PotentASN1 | Transitive only; never used |

SolidFoundation already provides:
- the dynamic value (`SolidData.Value`)
- the JSON, CBOR, and YAML formats
- URI templates (`URI.Template`)
- media types (`MediaType`, `MediaRanges`)
- big numbers

`Regex` comes from the standard library. The missing pieces are coding and the HTTP/URL pieces in
the companion documents.

### What already exists to build on

- **Event readers.** `FormatEventReader` (push bytes with `feedInput(_:isFinal:)`, pull events with
  `readEvent()`) yields `ParseEvent`s. Scalars are `ScalarRef`s that reference `ParseBuffer.Region`s
  without copying. JSON, CBOR, and YAML all implement it.
- **Event writers.** `FormatEventWriter`, `BufferedStreamEncoder`, `FormatStreamWriterDriver`.
- **Async drivers.** `FormatStreamReaderDriver` and the document stream readers over SolidIO
  `Source`/`Sink`.
- **Schema.** A compiled JSON Schema 2020-12 implementation with a `bytes` instance type and Solid
  keywords already reserved: `units`, `bitWidth`, `encoding`, `minSize`, `maxSize`.
- **`feature/coding` (53ecd83, unmerged).** An early sketch of a schema-driven design. See
  [Salvage](#salvage-from-featurecoding).

## Requirements

1. **Performance.** Static typing wherever possible; value types; no per-container allocation;
   scalars decode straight from buffer regions.
2. **Streaming.** Built on SolidData's events. No intermediate `Value` tree for typed data. One
   stack-local slot per property, filled in event order, then a final step that checks presence and
   nullability.
3. **Schema-based.**
   - Decode or encode and validate in one pass.
   - Every representation choice is a schema keyword.
   - Type code never restates constraints.
4. **Developer experience.**
   - Little code to write by hand. Macros cover the common cases.
   - Generated code looks like hand-written code.
   - Every `SolidCoding` type is also `Codable`.
5. **Platforms and dependencies.** Apple 26 platforms and Linux. Only Apple- or swift-server-backed
   third-party packages; `swift-syntax` is the only new one.
6. **Completeness.** Every supporting standard (RFCs, WHATWG specs) is implemented completely, with
   its conformance corpus or RFC examples as tests. A standard that is not supported fails loudly
   (`unsupported…`) and is never half-implemented.

### Non-goals

- Async decoding inside a single document in the first version ([Input modes](#input-modes)).

## Module Placement

```
SolidCoding
  ├─ SolidData      (events, Value, Pointer, JSON Patch, Merge Patch)
  ├─ SolidSchema    (evaluator, coding plans, type binding, vocabulary)
  ├─ SolidJSON, SolidCBOR, SolidYAML   (format entry points)
  ├─ SolidTempo, SolidID, SolidURI, SolidNumeric, SolidNet   (leaf codecs)
  └─ SolidCodingMacros (plugin) → swift-syntax 602.x
SolidHTTP → SolidCoding   (Problem, SSE, multipart, form format)
```

- **Leaf codecs** live in `SolidCoding`. Leaf modules stay free of coding dependencies.
- **Format entry points** live in `SolidCoding`. This keeps `SolidJSON`, `SolidCBOR`, and
  `SolidYAML` lightweight: usable for `Value` parsing without pulling in schema, Tempo, ID, and the
  rest.
  - `SolidSchema` no longer depends on `SolidJSON`. Its only uses (`contentMediaType` checking and
    directory schema loading) become format-agnostic; see
    [the schema design](2026-10-01-schema-streaming-evaluation-design.md#format-agnostic-content-and-schema-resources).
  - So entry-point placement is a choice, not a constraint.
- **`Schema.Options.standard`** (JSON, YAML, CBOR formats registered) is provided by `SolidCoding`.
- **`swift-syntax`** uses a toolchain-matched range (`602.0.0..<603.0.0` for Swift 6.2). This
  replaces `feature/coding`'s `exact: "600.0.1"` pin, which conflicts with any consumer that uses
  macros.

## Architecture

```
                         Schema ──build──▶ CodingPlan ──bind──▶ TypeBinding<T>   (once, cached)
                                               │
 bytes ─▶ FormatEventReader ─▶ DecodingReader ─┴─▶ T.decode(from:) ─▶ T
            (JSON/CBOR/YAML)     │  plan cursor: representation + inline constraints
            or Swift Decoder ────┤  evaluator: residual keywords, in lockstep
                                 └  record/replay, path tracking

 T ─▶ t.encode(to:) ─▶ EncodingWriter ─▶ FormatEventWriter or Swift Encoder ─▶ bytes
```

1. **Plan.** `Schema.CodingPlan` (in `SolidSchema`) projects the schema into per-location
   representation and inline constraints. It also records a **residual** for keywords that need
   the full evaluator, such as `if`/`then`, `unevaluated*`, and `dependentSchemas`. It is built and
   bound to the Swift type once.
2. **Source and sink.** A `DecodingSource` is either the event reader (the fast path) or a Swift
   `Decoder`. An `EncodingSink` is either an event writer or a Swift `Encoder`.
3. **Reader and writer.** `DecodingReader`/`EncodingWriter` combine a source or sink, a cursor into
   the plan, and an evaluator for residual keywords. Scalar reads apply the location's codec and
   constraints automatically.
4. **Type code.** Macro-generated or hand-written. It maps fields to slots and nothing else.

## Solid Coding Vocabulary

Publish a Solid coding vocabulary and meta-schema, starting from `feature/coding`'s
`MetaSchema-Solid-2020-12`. Every keyword below is enforced by the evaluator and by coding plans.

### How representation is chosen

- `format` (with `type`) picks the **Swift semantic type**.
- `type` picks the **wire shape**: `string`, `integer`, `number`, `bytes`, `boolean`, `null`,
  `array`, or `object`.
- `units`, `encoding`, `bitWidth`, and `signed` refine the wire shape.
- `representations` overrides those representation keywords for `text` formats, `binary` formats,
  or one specific format. Settings cascade down `any → text/binary → format`, and a descendant overrides only the keywords it sets. `tag` selects a CBOR or YAML tag. See
  [representations and tags](2026-10-01-representations-and-tags-design.md).
- When `type` allows several shapes, the decoder accepts any of them. The encoder writes the
  **first** non-null shape listed, unless overridden per call.

### Keywords

| Keyword | Status | Applies to | Meaning |
| --- | --- | --- | --- |
| `bytes` instance type | exists | — | Native byte strings in binary formats |
| `minSize` / `maxSize` | exists | `bytes`, text-encoded binary | Byte-length constraints, measured after decoding |
| `bitWidth` | exists (annotation) → coding | `integer`, `number` | 8, 16, 32, 64, 128. Add `8` to the allowed sizes. |
| `signed` | new | `integer` | `false` selects unsigned widths. Default `true`. |
| `units` | exists (annotation) → coding | numeric date/time and duration | `s`, `ms`, `us`, `ns`, `d` |
| `encoding` | reserved → coding | binary carried in `string` | `base64`, `base64url`, `base32`, `base32hex`, `base16` (RFC 4648). `contentEncoding` stays an annotation. |
| `unknownProperties` | new | `object` | `preserve`, `skip`, or `reject`. `additionalProperties: false` or `unevaluatedProperties: false` imply `reject`. |
| `unknownValues` | new | `enum` | `reject` (default) or `preserve` |
| `discriminator` | new | `object` with `oneOf`/`anyOf` | `{ "propertyName": "...", "mapping": { "value": "$ref" } }`, the same shape as OpenAPI; or `{ "tag": { … } }` in tag-capable formats |
| `representations` | new | any | Overlays of representation keywords keyed by `text`, `binary`, or a `FormatID`. Assertions stay in the base schema. |
| `tag` | new | any | A registered `TagType` name, or a native tag inside a format-specific overlay. Validated against the tag's content rules. |

### Format values

| `format` | Swift type | String form | Numeric form (`units`) | CBOR tags available |
| --- | --- | --- | --- | --- |
| `date-time` | `OffsetDateTime` | RFC 3339 | epoch, offset `Z` | tag 0 / tag 1 |
| `instant` (Solid) | `Instant` | RFC 3339 `Z` | epoch | tag 1 |
| `zoned-date-time` (Solid) | `ZonedDateTime` | RFC 9557 | — | — |
| `local-date-time` (Solid) | `LocalDateTime` | ISO 8601 extended | — | — |
| `date` | `LocalDate` | `full-date` | epoch days (`d`) | tag 1004 / tag 100 |
| `time` | `OffsetTime` | `full-time` | — | — |
| `local-time` (Solid) | `LocalTime` | `partial-time` | nanoseconds of day | — |
| `duration` | `PeriodDuration` | ISO 8601 | `Duration` in `units` | — |
| `http-date` (Solid) | `Instant` | IMF-fixdate | — | — |
| `uuid` | `SolidID.UUID` | canonical | — | tag 37, or 16 bytes with `type: bytes` |
| `uri`, `uri-reference`, `iri`, `iri-reference` | `URI` | as-is | — | tag 32 |
| `decimal` (Solid) | `BigDecimal` | decimal string | number | tag 4 |
| `big-integer` (Solid) | `BigInt` | decimal string | number | tag 2 / tag 3 |
| `media-type` (Solid) | `MediaType` | serialized | — | — |

All textual forms are specified completely in the [Tempo formats design](2026-10-01-tempo-formats-design.md)
and [RFC 4648](https://www.rfc-editor.org/rfc/rfc4648). Tags are emitted only when a representation
selects them.

```json
{
  "$id": "https://example.com/schemas/pet",
  "type": "object",
  "properties": {
    "name": { "type": "string", "pattern": "^[A-Za-z ]+$", "maxLength": 64 },
    "age": { "type": ["integer", "null"], "minimum": 0, "maximum": 40, "bitWidth": 16 },
    "adopted": {
      "type": "string", "format": "date-time",
      "representations": {
        "binary": { "type": "integer", "units": "s" },
        "cbor": { "type": "integer", "units": "s", "tag": 1 }
      }
    },
    "photo": {
      "type": "string", "encoding": "base64url", "maxSize": 1048576,
      "representations": { "binary": { "type": "bytes" } }
    },
    "tags": { "type": "array", "items": { "type": "string" } }
  },
  "required": ["name", "adopted"],
  "unknownProperties": "preserve"
}
```

## Reading

### `DecodingReader`

```swift
public struct DecodingReader<Source: DecodingSource & ~Copyable>: ~Copyable {
  public init(_ source: consuming Source, plan: Schema.CodingPlan.Node, options: DecodingOptions = .default)

  // Structure (the plan cursor moves with these)
  public mutating func beginObject<T>(_ binding: TypeBinding<T>) throws(CodingError) -> ObjectCursor
  public mutating func beginArray() throws(CodingError) -> ArrayCursor
  public mutating func decodeNull() throws(CodingError) -> Bool
  public mutating func skipValue() throws(CodingError)

  // Values: representation and constraints come from the plan at the current location
  public mutating func decode<T: SchemaDecodable>(_: T.Type) throws(CodingError) -> T
  public mutating func decodeNullable<T: SchemaDecodable>(_: T.Type) throws(CodingError) -> T?
  public mutating func decodeValue() throws(CodingError) -> Value       // lossless capture

  // Polymorphism
  public mutating func peekKind() throws(CodingError) -> EventKind
  public mutating func record<R>(_ body: (inout Self) throws(CodingError) -> R) throws(CodingError) -> (R, Recording)
  public mutating func replaying<R>(_ recording: consuming Recording,
                                    _ body: (inout Self) throws(CodingError) -> R) throws(CodingError) -> R
}

public protocol DecodingSource: ~Copyable {       // implemented by EventDecodingSource<R> and CodableDecodingSource
  mutating func nextStructure() throws(CodingError) -> StructureEvent
  mutating func integer<T: FixedWidthInteger>(_: T.Type) throws(CodingError) -> T
  mutating func float<T: BinaryFloatingPoint>(_: T.Type) throws(CodingError) -> T
  mutating func string() throws(CodingError) -> String
  mutating func withUTF8<R>(_ body: (UTF8Span) throws -> R) throws(CodingError) -> R
  mutating func bytes() throws(CodingError) -> Data
  mutating func decimal() throws(CodingError) -> BigDecimal
  // …bool, null, tags, peek
}
```

- Primitive Swift types (`Bool`, `String`, the `Int`/`UInt` family, `Float16`/`32`/`64`) are
  `SchemaDecodable` through built-in codecs. `decode(Int16.self)` reads an `Int16` directly. That
  makes `bitWidth` free, and range, `multipleOf`, and `enum` are checked from the plan.

### Typed scalar access

Today the only way to read a `ScalarRef` is `materialize(using:) -> Value`. Add typed requirements
to `ScalarResolver`, with defaults that go through `Value`:
- integer of any width, float, string, bytes, decimal
- `withUTF8`, to match keys and enum values and check patterns without creating a `String`

JSON parses integers from the region's digits into the target width; overflow becomes
`outOfRange`. CBOR reads the major-type argument directly. Unescaped JSON strings
(`Metadata.stringContainsEscapes == false`) are already valid UTF-8 in the buffer.

On the write side, `FormatEventWriter` gets the matching fast paths (`writeInteger`, `writeFloat`,
`writeString(UTF8Span)`, `writeBytes`), with defaults through `EmitEvent.scalar(Value)`.

### Key matching, paths, record/replay

- **Keys.** The plan's key table (precomputed per object node) maps UTF-8 key bytes to the bound
  field index. Known keys never become `String`s.
- **Paths.** The reader keeps a stack of key and index components that refer to the buffer. They
  turn into a `Pointer` only when an error is thrown.
- **Record/replay.** Used for a discriminator that arrives late, and for `oneOf` across object
  shapes. Events of the current subtree are captured with their buffer regions kept alive. The
  encoder always writes the discriminator first, so `SolidCoding`-produced input takes the
  no-buffering path.

### Input modes

1. **Whole document in memory** (request and response bodies). Synchronous decode, zero-copy
   scalars.
2. **Element streams.** An async driver over a SolidIO `Source` frames one element at a time and
   decodes it synchronously. Memory use is bounded by the largest element. Framings:
   - top-level JSON array
   - [JSON Text Sequences](https://www.rfc-editor.org/rfc/rfc7464) (`application/json-seq`,
     including recovery from truncated elements as RFC 7464 §2.4 requires)
   - [NDJSON / JSON Lines](https://github.com/ndjson/ndjson-spec)
   - [CBOR Sequences](https://www.rfc-editor.org/rfc/rfc8742) (`application/cbor-seq`)
   - YAML 1.2.2 multi-document streams
   - SSE `data` fields ([HTTP support](2026-10-01-http-support-design.md#server-sent-events-whatwg-html-92))
3. **Async inside a single document** is deferred. If needed, the macro can emit an `async`
   overload from the same declaration.

## Decoding and Encoding Types

```swift
public protocol SchemaDecodable: ~Copyable {
  static func decode<S: DecodingSource & ~Copyable>(from reader: inout DecodingReader<S>) throws(CodingError) -> Self
}
public protocol SchemaEncodable {
  func encode<S: EncodingSink>(to writer: inout EncodingWriter<S>) throws(CodingError)
}
public typealias SchemaCodable = SchemaDecodable & SchemaEncodable

public protocol SchemaBound {
  static var schema: Schema { get }                 // where the plan comes from
  static var fields: [FieldDescriptor] { get }      // structure, for binding
}
```

### Property slots

`Slot<T>` is a three-state stack value: `absent`, `null`, or `value(T)`. Presence and nullability
rules come from the plan and are checked when the object ends. A slot converts to the Swift
property:

| Swift property | absent | null | value |
| --- | --- | --- | --- |
| `T` | must be required, or have a schema `default` (checked at binding) | invalid unless the plan allows `null` (then binding fails) | `v` |
| `T?` | `nil` | `nil` | `v` |
| `T = d` | `d` (or the schema `default` if declared) | `d` if nullable | `v` |
| `PatchOp<T>` / `UpdateOp<T>` | `.keep` | `.delete` / invalid | `.set(v)` |

`PatchOp`, `UpdateOp`, and `MergeOp` are specified in the [JSON Patch design](2026-10-01-json-patch-design.md).

### Example: authoring

```swift
#schemaNamespace("https://example.com/schemas/")      // once per module

@SchemaCodable(name: "pet")                           // $id: https://example.com/schemas/pet
public struct Pet: Sendable, Hashable {
  @Field(.string(pattern: "^[A-Za-z ]+$", maxLength: 64))
  public var name: String

  @Field(.integer(minimum: 0, maximum: 40))
  public var age: Int16?

  @Field(.dateTime(.rfc3339(), binary: .epoch(.seconds),
                   formats: [.cbor: .tagged(.cbor.epochDateTime, .epoch(.seconds))]))
  public var adopted: OffsetDateTime

  @Field(.binary(text: .base64url, maxSize: 1 << 20))
  public var photo: Data?

  public var tags: [String] = []

  @UnknownProperties public var extensions: Value.Object = [:]
}
```

`Pet.schema` is generated from these attributes and the Swift types, and it equals the JSON Schema
shown above:
- `required` comes from non-optional properties without defaults.
- `bitWidth: 16` and the `null` type come from `Int16?`.
- `unknownProperties: preserve` comes from `@UnknownProperties`.

The same type could instead point at an explicit schema, for example
`@SchemaCodable(schema: .literal(...))`, and drop every `@Field` option.

### Field options

`@Field` is a marker peer macro. `@SchemaCodable` reads it, and it expands to nothing. It has two
overloads: annotations only, and annotations plus a type-specific options value.

```swift
@attached(peer) public macro Field(
  name: String? = nil, description: String? = nil, deprecated: Bool = false, access: FieldAccess = .readWrite)
@attached(peer) public macro Field<Options: FieldOptions>(
  _ options: Options,
  name: String? = nil, description: String? = nil, deprecated: Bool = false, access: FieldAccess = .readWrite)

public protocol FieldOptions: Sendable {
  associatedtype Subject                                    // the Swift type these options configure
  func contribute(to property: inout SchemaBuilder.Property) // writes schema keywords
}

public protocol FieldConfigurable {
  associatedtype FieldOptions: SolidCoding.FieldOptions
  static var defaultFieldSchema: SchemaBuilder.Property { get }   // type, format, bitWidth, …
}
```

- **Type-specific options.** Each configurable type names its options type: `Data` →
  `BinaryFieldOptions`, `OffsetDateTime` → `DateTimeFieldOptions`, the `Int` family →
  `IntegerFieldOptions<Self>`, and so on.
  - `Optional`, `Array`, `Set`, and `Dictionary` forward to their element's options. Collections
    wrap them for their own constraints (`.array(minItems:items:)`).
  - Factories are constrained static members ([SE-0299](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0299-extend-generic-static-member-lookup.md)),
    such as `extension FieldOptions where Self == BinaryFieldOptions { static func binary(...) }`.
    That is why `@Field(.binary(...))` reads naturally.
- **Type checking against the property.** The generated schema code is
  `SchemaProperty("photo", Data?.self, options: .binary(text: .base64url))`, whose initializer is
  `init<T: FieldConfigurable>(_: String, _: T.Type, options: T.FieldOptions)`. A `.dateTime(...)`
  option on a `Data` property does not compile.
  - Errors inside macro expansions are hard to read. So the macro also checks the built-in
    factories syntactically against the declared type, and reports at the attribute: "`.dateTime`
    cannot configure `Data`; use `.binary(...)`."
  - The generated code is the backstop for user-defined options.
- **Extensible.** A user type conforms to `FieldConfigurable`, declares an options type, and adds a
  factory. Its `contribute(to:)` may write the user's own vocabulary keywords.
- **Representation targeting.** Options with representation choices take a `Targeted<Encoding>`
  shape (`all`, `text:`, `binary:`, `formats:`), so "RFC 3339 everywhere, epoch seconds in binary,
  tag 1 in CBOR" is one attribute. See
  [Swift spelling](2026-10-01-representations-and-tags-design.md#swift-spelling).

Built-in options:

| Swift type | Options | Notes |
| --- | --- | --- |
| `String` | `.string(minLength:maxLength:pattern:format:)` | |
| `Int*`/`UInt*` | `.integer(minimum:maximum:exclusiveMinimum:exclusiveMaximum:multipleOf:)` | `bitWidth`/`signed` come from the Swift type |
| `Float*`/`Double` | `.number(...)` | |
| `Data` | `.binary(text:binary:formats:minSize:maxSize:)` | |
| Tempo types | `.dateTime(...)`, `.date(...)`, `.time(...)`, `.duration(...)` | `Targeted<…Encoding>` |
| `SolidID.UUID`, `URI`, `MediaType` | `.uuid(...)`, `.uri(...)`, `.mediaType(...)` | |
| `BigInt`/`BigDecimal` | `.decimal(...)` | string or number per format |
| arrays, sets | `.array(minItems:maxItems:uniqueItems:items:)` | |
| maps | `.map(minProperties:maxProperties:propertyNames:values:)` | |
| string enums | `.enumeration(unknownValues:)` | |
| `Value` | `.any(schema:)` | optional sub-schema for free-form data |

The annotation labels map to schema annotations:
- `name` → wire property name
- `description` → `description`
- `deprecated` → `deprecated`
- `access` → `readOnly`/`writeOnly`

Property initializers become schema defaults; see [Defaults](#defaults).

### Example: expansion

```swift
extension Pet: SchemaDecodable, SchemaEncodable, SchemaBound {
  public static let fields: [FieldDescriptor] = [
    .init("name", String.self), .init("age", Int16?.self), .init("adopted", OffsetDateTime.self),
    .init("photo", Data?.self), .init("tags", [String].self), .unknownProperties,
  ]
  public static let schema: Schema = SchemaComposer.object(    // built once from fields + options
    Pet.self, id: .derived(Pet.self, name: "pet", namespace: __solidSchemaNamespace),
    unknown: .preserve, properties: [
      SchemaProperty("name", String.self, options: .string(pattern: "^[A-Za-z ]+$", maxLength: 64)),
      SchemaProperty("age", Int16?.self, options: .integer(minimum: 0, maximum: 40)),
      SchemaProperty("adopted", OffsetDateTime.self, options: .dateTime(/* … */)),
      SchemaProperty("photo", Data?.self, options: .binary(text: .base64url, maxSize: 1 << 20)),
      SchemaProperty("tags", [String].self, default: []),
    ])
  static let binding = TypeBinding.cached(for: Pet.self)          // builds plan + binding once; throws at first use

  public static func decode<S>(from reader: inout DecodingReader<S>) throws(CodingError) -> Pet {
    var name = Slot<String>(), age = Slot<Int16>(), adopted = Slot<OffsetDateTime>()
    var photo = Slot<Data>(), tags = Slot<[String]>(), extensions = Value.Object()

    var object = try reader.beginObject(binding.get())
    while let field = try object.nextField(&reader) {
      switch field {
      case 0: try name.set(reader.decode(String.self))                  // pattern, maxLength from plan
      case 1: try age.set(reader.decodeNullable(Int16.self))            // range from plan
      case 2: try adopted.set(reader.decode(OffsetDateTime.self))       // epoch ms, chosen by plan
      case 3: try photo.set(reader.decodeNullable(Data.self))           // base64url or bytes, by shape
      case 4: try tags.set(reader.decode([String].self))
      default: try object.unknown(&reader, into: &extensions)           // policy from plan
      }
    }
    try object.end(&reader)                                              // required, residual keywords
    return Pet(name: name.get(), age: age.get(), adopted: adopted.get(),
               photo: photo.get(), tags: tags.get(default: []), extensions: extensions)
  }

  public func encode<S>(to writer: inout EncodingWriter<S>) throws(CodingError) {
    var object = try writer.beginObject(Self.binding.get())
    try object.field(0, name, &writer)
    try object.field(1, age, &writer)
    try object.field(2, adopted, &writer)
    try object.field(3, photo, &writer)
    try object.field(4, tags, &writer)
    try object.unknown(extensions, &writer)
    try object.end(&writer)
  }
}
```

### Schema sources for `@SchemaCodable`

| `schema:` | Meaning | Typical user |
| --- | --- | --- |
| `.attributes` (default) | Generated at runtime from the Swift types plus `@Field` options ([Field options](#field-options)) | Hand-written models |
| `.literal(...)` | Inline `Schema.Builder.build(constant:)` literal | Generated code (no resources; works on Linux) |
| `.resource(bundle:path:)` | JSON/YAML schema file in a bundle | Teams that share schema files |
| `.id(URI)` | Looked up in `SchemaRegistry` (registered literals or resources) | Shared or `$ref`-heavy schemas |

With an explicit schema (`.literal`, `.resource`, `.id`), the schema is authoritative. `@Field` may
then carry only `name:`, to map a Swift property name to a different wire name. Option arguments
are a macro error.

Schemas are composed and resolved at runtime, so the macro never parses JSON. User-defined
`FieldOptions` contribute keywords through ordinary code. The macro also
emits a test helper (`Pet.validateBinding()`) that forces plan building and binding, so mismatches
between the Swift declaration and the schema fail in unit tests. Binding is described in the
[schema design](2026-10-01-schema-streaming-evaluation-design.md#binding-a-swift-type-to-a-plan).

### Schema IDs and references

Schema `$id`s are **derived** by default.

- **ID shape:** `<namespace><name>`.
  - `name` is the type's Swift path below its nearest namespaced ancestor. That is `Dog` inside a
    namespaced `Pets`, or `API.Pets.Dog` when no enclosing type sets a namespace.
  - `@SchemaCodable(name:)` pins the name, so a Swift rename doesn't change the ID.
  - `@SchemaCodable(id:)` sets the whole ID for one-off cases.
- **Module namespace:** `#schemaNamespace("https://example.com/schemas/")` is a freestanding
  declaration macro, written once per module at file scope. It expands to an internal
  `__solidSchemaNamespace` constant.
  - `SolidCoding` exports a public fallback with the same name, meaning
    `urn:swift:<Module>.`, with the module derived at runtime from `String(reflecting:)`.
  - The module-local declaration shadows the imported one.
- **Type namespaces:** `@SchemaNamespace("pets/")` on any enclosing type, whether a plain `enum`
  used as a namespace or a `SchemaCodable` type (`@SchemaCodable(namespace:)` is the same thing).
  - **Resolution** works like JSON Schema `$id`. A relative value is resolved against the next
    namespace outward (RFC 3986 §5), ending at the module namespace. An absolute value starts a
    new root:

    ```swift
    #schemaNamespace("https://example.com/schemas/")

    @SchemaNamespace("pets/")
    enum Pets {
      @SchemaCodable struct Dog { … }                 // https://example.com/schemas/pets/Dog
      @SchemaNamespace("v2/")
      enum V2 { @SchemaCodable struct Dog { … } }     // https://example.com/schemas/pets/v2/Dog
    }
    ```

  - **Why an attached macro and not `#schemaNamespace` inside the type:**
    - A relative member named `__solidSchemaNamespace` would have to reference the outer
      declaration of the same name from its own initializer, which is circular.
    - The runtime resolver needs a conformance, which only an attached macro can add.
  - **Mechanism:**
    - `@SchemaNamespace` adds `SchemaNamespaceProviding` and a static `schemaNamespace`.
    - `@SchemaCodable` reads the enclosing type names from the macro's `lexicalContext`
      (swift-syntax 600+). It emits `SchemaNamespace.resolve(enclosing: [Pets.self, Pets.V2.self])`,
      which walks outward through providers to the module constant.
  - **Export:** when an enclosing type is itself `SchemaBound`, `schemaBundle` embeds its nested
    types as embedded schema resources (their own `$id`s under the outer schema's `$defs`). That
    mirrors the Swift nesting in the JSON Schema document.
- **Spike** on Swift 6.2: global-scope freestanding macros with `named` declarations, the
  module-local shadowing rule, and `lexicalContext` contents for nested and extension contexts.
- **References are by type, never by string.** Renaming a Swift type therefore never breaks a
  reference inside the program.
  - A property whose type is `SchemaBound` emits `$ref` to that type's derived ID automatically.
  - Wherever a schema needs another type (`.any(schema:)`, discriminator mappings, the explicit
    literal builder), it accepts `.ref(Owner.self)`, or just `Owner.self`:

  ```swift
  @Field(.any(schema: .ref(Owner.self)))      public var previousOwner: Value?
  @Discriminated(property: "kind", mapping: ["dog": Dog.self, "cat": Cat.self])

  @SchemaCodable(schema: .literal([
    "type": "object",
    "properties": ["owner": ["$ref": .ref(Owner.self)]],     // resolved to Owner's $id at runtime
  ]))
  ```

  - A referenced type registers its schema in `SchemaRegistry` the first time `schema` is touched.
    So `$ref` resolution and `schemaBundle` find every referenced type with no manual registration.
- **External consumers** (other services, published schema files) see the derived IDs. Pin
  `name:` on any type whose schema is published, so Swift renames stay internal.

### Defaults

Swift property initializers are the way to declare defaults.

- **What becomes a schema `default`:** literal-like initializers.
  - Literals, collection literals, and `nil`.
  - Enum cases and static members referenced without a call (`.active`, `.zero`).
  - The value is encoded when the schema is built, through the property's own codec in the base
    representation. So a `Date`-typed default produces the right wire form.
- **What stays Swift-only:** initializers that call something (`Date.now`, `UUID()`). Baking a
  snapshot of them into the schema would be wrong, so they are never emitted.
- **Decoding an absent property** yields the schema `default` when there is one, and the Swift
  initializer otherwise. With attribute-generated schemas the two are the same value.
- **Encoding:** defaults are written unless `EncodingOptions.omitDefaults` is set.
- **Conflicts** are only possible with an explicit schema (`.literal`, `.resource`, `.id`).
  `@SchemaCodable(defaults:)` chooses the policy, and binding enforces it:

  | Policy | Literal Swift initializer ≠ schema `default` | Non-literal Swift initializer + schema `default` |
  | --- | --- | --- |
  | `.mustMatch` (default) | `BindingError.defaultConflict` (compared with `jsonEquals` after encoding) | Allowed. The schema default governs the wire; the Swift initializer governs construction. Binding records a warning. |
  | `.preferSchema` | Schema default wins on decode | Same |
  | `.preferSwift` | Swift value wins on decode, and the exported schema's `default` is rewritten to match | Swift value wins; exported `default` removed |

- **Required:** a property with any default is never `required`.

### Schema export

Every `SchemaBound` type exposes its schema for interop: OpenAPI components, documentation,
external validators.

```swift
Pet.schema                                   // compiled Schema
Pet.schemaDocument                           // Value: this type's JSON Schema; nested SchemaBound types are $refs to their $id
Pet.schemaBundle(dialect: .draft2020_12)     // compound document, referenced types embedded under $defs (JSON Schema 2020-12 §9.3)
```

`schemaDocument` is the **fragment**: it is self-describing through `$id`, and other schemas can
embed it or `$ref` it. `schemaBundle` is the standalone, fully resolved export.

### Containers and special shapes

- **Arrays and sets.** Item plans and count constraints come from the plan. `uniqueItems` on a
  `Set` uses `Hashable`; on arrays it uses a seen-set.
- **Maps.** `[String: T]` and `OrderedDictionary<String, T>` use `propertyNames` and
  `min`/`maxProperties` from the plan.
- **Enums.** String enums match UTF-8 bytes against the plan's `enum` table. With
  `unknownValues: preserve`, the macro requires an `unknown(String)` case.
- **Discriminated families.** `@Discriminated` on an enum with associated values. Dispatch comes
  from the plan's discriminator table, with a fallback case holding the raw `Value.Object`.
- **Unions.** Scalar unions dispatch on `peekKind()`. Object unions use record/replay, and the
  error lists every branch's failure.
- **Free-form `Value`.** Captured losslessly. Validated by the evaluator against the location's
  schema.
- **Recursion.** Recursive types are `indirect enum`s or `final class`es. Classes get a
  macro-emitted designated initializer that takes the slots.

## Codable Integration

### Every `SolidCoding` type is `Codable`

`@SchemaCodable` emits `Codable` conformance implemented **by SolidCoding**, so the schema still
decides representation and validation:

```swift
// member macro (members suppress compiler synthesis even when the type itself declares Codable)
public init(from decoder: any Decoder) throws {
  var reader = DecodingReader(CodableDecodingSource(decoder), plan: Self.binding.get().plan,
                              options: .init(userInfo: decoder.userInfo))
  self = try Self.decode(from: &reader)
}
public func encode(to encoder: any Encoder) throws {
  var writer = EncodingWriter(CodableEncodingSink(encoder), plan: Self.binding.get().plan,
                              options: .init(userInfo: encoder.userInfo))
  try encode(to: &writer)
}
// extension macro: `extension Pet: Codable {}`, only when not already declared
```

`CodableDecodingSource` maps reader operations onto Swift containers:

| Reader operation | Swift `Decoder` call |
| --- | --- |
| `beginObject` / `nextField` | `container(keyedBy: DynamicCodingKey.self)`, iterating `allKeys` |
| `beginArray` | `unkeyedContainer()` |
| integer / float / string / bool | `decode(Int16.self …)` etc., with the exact Swift type the plan selected |
| bytes (`type: bytes` shape) | `decode(Data.self …)`; the coder's data strategy applies |
| bytes (text `encoding`), dates, UUIDs, URIs, decimals | decoded as `String`/number and converted by the plan's codec |
| nested `SolidCoding` type | the **same** reader continues through `nestedContainer`, so the containing plan location still governs; nested `init(from:)` is never called |
| free-form `Value` | probing in a fixed order: nil → Bool → Int64 → UInt64 → Decimal/Double → String → keyed → unkeyed |

- **Validation** still runs: the source reports each structure and scalar to the evaluator as an
  event.
- **Encoder-wide strategies don't matter.** `JSONEncoder.dateEncodingStrategy` and similar never
  see a date, because the plan has already chosen its representation. The one exception is native
  `bytes`, where the coder's `Data` strategy is the only option `Codable` offers.
- **Fidelity limits** apply only on this path and are documented:
  - key order depends on the decoder (`JSONDecoder` does not preserve it);
  - free-form numbers are limited to what the coder exposes;
  - unknown-property preservation is best-effort.
  The event path has none of these limits.
- **Classes** get `required init(from:)` that delegates to the macro-emitted slot initializer.
- **Hand-written conformers** that don't use the macro can opt in to the default implementation:
  `extension Decodable where Self: SchemaDecodable & SchemaBound { init(from:) }`. Whether a
  constrained protocol-extension witness reliably takes precedence over synthesis must be verified
  in a spike. The macro path does not depend on it.

### `Codable` types inside `SolidCoding` types

A field whose type is only `Codable`, such as a third-party model, is supported through
`CodableCodec<T>`. The subtree is captured as a `Value`, then decoded with `ValueDecoder`, a Swift
`Decoder` over `Value`. Encoding goes through `ValueEncoder`. The location's schema is still
evaluated. `ValueEncoder`/`ValueDecoder` are public, and also serve as the general
`Codable` ↔ `Value` bridge.

## Writing

`EncodingWriter<S: EncodingSink>` mirrors the reader.
- **Order.** Properties are written in field order, with the discriminator first.
- **Absent and null.**
  - `nil` is omitted unless the plan says the property is required and nullable.
  - `PatchOp.keep` is omitted, and `.delete` is written as null.
- **Shapes.** Each scalar is written in the plan's preferred shape.
  The preferred shape for the target format comes from `representations`.
  `EncodingOptions.preferredShapes` can still override it per call.
- **Validation.** `EncodingOptions.validate` runs the plan's inline constraints and the residual
  evaluator. It defaults to on in debug builds and off in release builds.

## Leaf Codecs

| Swift type | Representations (selected by the plan) |
| --- | --- |
| `Bool`, `String`, `Int*`/`UInt*`, `Float16`/`32`/`64` | native |
| `Data` | native bytes; RFC 4648 text encodings |
| `BigInt`, `BigUInt`, `BigDecimal` | number; decimal string; CBOR tags 2/3/4 |
| `Instant`, `OffsetDateTime`, `ZonedDateTime`, `LocalDate`, `LocalTime`, `LocalDateTime`, `OffsetTime` | see the [Tempo formats design](2026-10-01-tempo-formats-design.md) |
| `Duration`, `PeriodDuration` | ISO 8601; number with `units` |
| `SolidID.UUID` | canonical string; 16 bytes; CBOR tag 37 |
| `URI` | string; CBOR tag 32 |
| `MediaType` | serialized string |
| `Value` | lossless capture and emission |
| `Problem`, `PatchOp`/`UpdateOp`/`MergeOp`, `JSONPatch`, `MergePatch` | see the companion documents |

## Entry Points

```swift
JSON.decode(Pet.self, from: data)                 // Data, String, [UInt8]
JSON.encode(pet) -> Data
JSON.encode(pet, to: sink) async throws
CBOR.decode(Pet.self, from: data); CBOR.encode(pet)
YAML.decode(Pet.self, from: string); YAML.encode(pet)

JSON.decodeElements(Pet.self, from: source)       // AsyncThrowingStream<Pet, Error>
JSON.decodeSequence(Pet.self, from: source)       // RFC 7464
JSON.decodeLines(Pet.self, from: source)          // NDJSON / JSON Lines
CBOR.decodeSequence(Pet.self, from: source)       // RFC 8742
YAML.decodeDocuments(Pet.self, from: source)

let coder = Schema.ValueCoder(schema: schema)     // schema-only, no Swift types
```

`CodingFormat` (a reader factory plus a writer factory) lets other formats join. Sunday's
media-type registry maps `MediaType` to `any CodingFormat`; the existential cost is once per
request.

## Errors

```swift
public struct CodingError: Error, Sendable {
  public enum Kind: Sendable {
    case typeMismatch(expected: EventKind, found: EventKind)
    case missing, unexpectedNull, duplicateKey, unknownProperty, unknownValue
    case outOfRange, constraint(keyword: Schema.Keyword, message: String)
    case invalidRepresentation(String)
    case noMatchingVariant([CodingError])
    case binding(BindingError), plan(PlanError)
    case format(FormatError), codable(any Error)
  }
  public var kind: Kind
  public var instancePath: Pointer
  public var schemaPath: Pointer?           // keyword location, matching validator output
  public var location: FormatLocation?
}
```

`DecodingOptions.collectErrors` keeps decoding after a constraint failure and reports every
failure. Structural errors stop decoding.

## Performance

Benchmark with the existing `package-benchmark` setup against Foundation `JSONDecoder`/`JSONEncoder`
and PotentCodables:
- shapes: flat object, deep object, large array, free-form
- formats: JSON and CBOR
- paths: event path and the Codable path (through `JSONDecoder`)

Targets:
- A steady-state decode of a flat object allocates only the result and its payloads. Plans,
  bindings, and evaluator arenas are reused.
- Event-path decode throughput is at least 2× `JSONDecoder` on the large-array benchmark, with full
  validation on.

## Migration

### Salvage from feature/coding

- **Keep:**
  - `MetaSchema-Solid-2020-12`
  - the macro target layout
  - the attribute markers, reworked into `@Field(...)` schema spellings
- **Replace:**
  - the pointer-addressed `SchemaEncoder`/`SchemaDecoder`
  - `SchemaValueCoding.swift`
  - the Tempo conformances, which are mostly `fatalError()`

### Sunday runtime

- **Re-exports.** Sunday re-exports the Solid modules generated code uses
  (`@_exported import SolidCoding, SolidData, SolidHTTP, SolidNet, SolidURI, SolidTempo, SolidID,
  SolidNumeric`), so generated code imports only `Sunday`. Do not re-export the umbrella `Solid`
  module; its `enum Data` namespace and `SolidID.UUID` collide with Foundation.
- **Replacements:**

  | Sunday today | Replacement |
  | --- | --- |
  | `MediaTypeEncoder`/`Decoder` | a `CodingFormat` registry |
  | `AnyValue` | `Value` |
  | `Problem` | `SolidHTTP.Problem` + `ProblemRegistry` |
  | `UpdateOp`/`PatchOp` | the patch types |
  | Sunday's `MediaType` | `SolidNet.MediaType` |
  | `URITemplate` wrapper | `URI.Template` |
  | form/query encoding | `FormFormat` and `ParameterSerializer` |
  | SSE parser | `SSEParser` + `EventSourceSession` |
  | OSLog `Logger` | `SolidCore.Log` |

- **Linux transport.** AsyncHTTPClient (swift-server) over the same `Source`/`Sink` abstractions.
  This is outside SolidFoundation.

### Sunday generator

- **Models.**
  - Emit `@SchemaCodable(schema: .literal(...))` types.
  - Emit a module-level `#schemaNamespace` from generator options.
  - Express cross-type references as `.ref(T.self)` rather than ID strings.
  Constraints and representation move from hand-written validation code into the emitted schema.
- **Type mapping.**
  - RAML `date-only`, `time-only`, `datetime-only`, `datetime` → `LocalDate`, `LocalTime`,
    `LocalDateTime`, `OffsetDateTime`
  - `uuid` → `SolidID.UUID`; `uri` → `URI`; decimals → `BigDecimal`
  - integer `format`s → `bitWidth`/`signed` (this also fixes `number format: float` → `String`)
- **Other output.**
  - Patchable types emit `@MergePatchable`.
  - Problems emit `@ProblemType`.
  - Parameters emit OpenAPI style metadata for `ParameterSerializer`.
  - Multipart bodies emit part encodings.
- **No platform-specific output.** Drop the OSLog `privacy: .public` interpolation.
- **Codability diagnostics.** Run the same codability analysis at generation time, so
  non-codable schemas are generator diagnostics, not runtime failures.

### Dependency hygiene (SolidFoundation)

- Replace SWCompression on Linux (solo maintainer). zlib already uses `CZlib`; add system-library
  targets for the other algorithms, or drop them on Linux.
- Move build tools and lint (swift-argument-parser, swift-markdown, SwiftFormatPlugins) into a
  separate tools package.

## Phasing

Phases 1a–1d can run in parallel.

1. **Independent foundations**
   - a. Schema streaming evaluator; the tree validator becomes replay
     ([schema design](2026-10-01-schema-streaming-evaluation-design.md))
   - b. Tempo wire formats ([Tempo design](2026-10-01-tempo-formats-design.md))
   - c. Value-level JSON Patch and Merge Patch, including Pointer mutation and `jsonEquals`
     ([patch design](2026-10-01-json-patch-design.md))
   - d. Percent-encoding, the `FormFields` tuple layer, ordered URI-template values, and the
     uritemplate-test corpus ([URL/form design](2026-10-01-url-form-encoding-design.md))
2. **Coding plans.**
   - Solid vocabulary, including `representations` and `tag`
   - `FormatID`, `TagType`, `TagRegistry`, and tag validation in the CBOR and YAML readers/writers
   - per-format `CodingPlan`, codability analysis, `TypeBinding`
3. **SolidCoding core.**
   - typed `ScalarResolver` paths
   - `DecodingReader`/`EncodingWriter` with event and Codable sources and sinks
   - slots, leaf codecs, entry points, element streams
   - `ValueEncoder`/`ValueDecoder`
4. **Macros.** `@SchemaCodable` (with Codable), `@Field`, `@UnknownProperties`, `@Discriminated`,
   `@MergePatchable`, `@ProblemType`.
5. **Polymorphism and dynamic coding.** Record/replay and `Schema.ValueCoder`.
6. **Format layers.**
   - structured form format, `ParameterSerializer`, typed JSON Patch builder
   - [HTTP support](2026-10-01-http-support-design.md): fields, Problem, SSE, multipart
7. **Benchmarks, then the Sunday runtime and generator migration.**

## Open Questions

None at the hub level. Each companion document lists its own.

# Format-Targeted Representations and Tags

Part of the [SolidCoding design set](2026-09-30-solid-coding-design.md).

## Goal

A field's wire representation should be configurable:

- for **every** format;
- for a **kind** of format (`text` or `binary`);
- for **one specific** format (`cbor`, `yaml`, …).

Settings cascade down the format hierarchy (`any → text → json`, `any → binary → cbor`), and each node overrides only the keywords it sets. For example: "RFC 3339 strings everywhere, but epoch seconds in
binary formats, and epoch seconds with CBOR tag 1 in CBOR."

**Tags** (CBOR tags, YAML tags) should be first-class:
- typed, and either standard or user-defined;
- extensible by users;
- validated statically when a plan is built, and at runtime on both encode and decode.

A tag whose content rules forbid a value must never be written with it, for example CBOR tag 1
(epoch date/time) on a text string.

## Format Identity

`Format` has `kind: FormatKind` (`text`/`binary`) today, but no stable identifier. Add one:

```swift
public struct FormatID: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
  public static let json: FormatID = "json"
  public static let cbor: FormatID = "cbor"
  public static let yaml: FormatID = "yaml"
  public static let formURLEncoded: FormatID = "form-urlencoded"
  // future: "xml"
}

public protocol Format: Sendable {
  var id: FormatID { get }          // new
  var kind: FormatKind { get }
  func supports(type: ValueType) -> Bool
}
```

## Representation Hierarchy

Formats form a tree, and representation settings **cascade** down it:

```
any ─┬─ text ───┬─ json
     │          ├─ yaml
     │          └─ form-urlencoded
     └─ binary ─── cbor
```

```swift
public enum FormatSelector: Hashable, Sendable {
  case any
  case kind(FormatKind)            // .text, .binary
  case format(FormatID)
}

extension FormatID {
  /// Parent in the hierarchy. Defaults to the format's kind. A format may name another format as
  /// its parent (for example a future "json5" under "json"), so the tree can grow deeper.
  public var parent: FormatSelector { get }
}
```

- **Cascade per keyword.** A node inherits each representation keyword from its parent unless it
  sets that keyword itself. "Binary formats except CBOR" means: set it on `binary`, override on
  `cbor`. No combined selectors are needed.
- **Clearing.** `null` at a node removes an inherited keyword (decided: simple, and no
  representation keyword needs a literal `null` value). Example: `"tag": null` on one format
  under a `binary` that sets a tag.
- **Built-in defaults** are the bottom layer, chosen per kind (see
  [defaults](#defaults-when-nothing-is-specified)). Any explicit setting at any level overrides them.
  The base schema is the `any` node.
- **Applicability.** After resolution, a keyword that does not apply to the resolved `type` is
  handled by where it came from:
  - **Inherited:** dropped. A `units` inherited by a `string` overlay is ignored.
  - **Set on that same node:** a `PlanError`.
- **Plans are per format.** `CodingPlan`s are built and cached per `(schema, FormatID)`. The
  cascade is resolved once, at plan build.

## Schema Vocabulary

### `representations`

```json
"adopted": {
  "format": "date-time",
  "type": "string",
  "representations": {
    "binary": { "type": "integer", "units": "s" },
    "cbor": { "type": "integer", "units": "s", "tag": 1 }
  }
}
```

- **Keys** are `text`, `binary`, or a registered `FormatID`. They name nodes in the
  [hierarchy](#representation-hierarchy); nesting comes from the hierarchy, not from the JSON. The
  meta-schema enforces the allowed keys through `propertyNames`.
- **Values** are overlays restricted to **representation keywords**: `type`, `units`, `encoding`,
  `bitWidth`, `signed`, `tag`.
- **Assertions stay in the base schema.** Assertions are type-specific in JSON Schema (`maxLength`
  applies only to strings, `maximum` only to numbers), so a base `maxLength` does not affect an
  integer overlay. Overlays cannot add assertions; that keeps one set of constraints per field.
- **Validation semantics.**
  - With a target format (`Schema.Options.targetFormat`), the evaluator applies the keywords
    resolved by cascading from `any` down to that format.
  - With no target format (validating a free-standing `Value`), an instance is valid if it is valid
    under the base or any overlay, like `anyOf` across the representations.
- **`tag` outside an overlay** must name a registered `TagType` (`"tag": "pet"`). Inside a
  format-specific overlay it may be that format's native tag (`1` for CBOR, `"!pet"` for YAML).

### Defaults when nothing is specified

| Semantic type | text formats | binary formats |
| --- | --- | --- |
| bytes | `string` + `encoding: base64` | native `bytes` |
| date/time types | RFC 3339 / ISO 8601 string | same string, untagged |
| `decimal`, `big-integer` | decimal string | number (CBOR tags 4 / 2–3 only when `tag` is set) |
| `uuid` | canonical string | canonical string |

Tags are **never** emitted unless a representation selects one. Decoders accept tagged input that
matches the expected representation whenever the `TagPolicy` allows it (below).

## Tags

### Model (SolidData)

```swift
/// A concrete tag as it appears in one format.
public enum Tag: Hashable, Sendable {
  case cbor(UInt64)
  case yaml(YAMLTag)                 // resolved: global "tag:yaml.org,2002:timestamp" or local "!pet"
}

/// The semantic definition of a tag across formats.
public struct TagType: Hashable, Sendable {
  public let name: String                       // registry name, e.g. "epoch-date-time"
  public let origin: Origin
  public let identities: [FormatID: Tag]        // per-format identity
  public let content: TagContent                // what the tagged item may contain

  public enum Origin: Hashable, Sendable {
    case standard(reference: String)            // e.g. "RFC 8949 §3.4.2"
    case registered(registry: String)           // e.g. "IANA CBOR Tags", "yaml.org type repository (1.1)"
    case user
  }
}

public struct TagContent: Sendable {
  public var shapes: ShapeSet                    // .integer, .float, .string, .bytes, .array, .object …
  public var format: String?                     // e.g. "date-time" for CBOR tag 0
  public var byteLength: ClosedRange<Int>?       // e.g. 16...16 for UUID tag 37
  public var validate: (@Sendable (borrowing ContentView) -> TagValidity)?   // deep checks
}

public struct TagRegistry: Sendable {
  public static let standard: TagRegistry
  public func registering(_ type: TagType) throws(TagRegistryError) -> TagRegistry
  public func type(for tag: Tag) -> TagType?
  public func type(named name: String) -> TagType?
}
```

- **Storage is unchanged.** `Value.tagged(tags:value:)` still holds tags as `Value`s. The new
  methods `Value.tags(in: FormatID) -> [Tag]` and `Value.tagged(_ type: TagType, _ value: Value)`
  give a typed view.
- **Standard registry contents:**
  - CBOR, [RFC 8949](https://www.rfc-editor.org/rfc/rfc8949) §3.4: tags 0, 1, 2, 3, 4, 5, 21, 22,
    23, 24, 32, 33, 34, 36, 55799.
  - CBOR, [RFC 8943](https://www.rfc-editor.org/rfc/rfc8943): tags 100 and 1004.
  - CBOR, IANA-registered: 37 (UUID).
  - YAML 1.2.2 core schema tags: `str`, `int`, `float`, `bool`, `null`, `seq`, `map`.
  - YAML 1.1 type repository tags still in wide use: `binary`, `timestamp`, `set`, `omap`, `pairs`.
    These are marked `.registered`, because they are not part of YAML 1.2.
- **User tags.**
  - `TagType.user(...)` rejects a CBOR number already in the registry.
  - It warns for numbers below 32768, the specification-required range in RFC 8949 §9.2.
  - YAML user tags are local (`!pet`) or global `tag:` URIs ([RFC 4151](https://www.rfc-editor.org/rfc/rfc4151)),
    and their syntax is validated.

```swift
extension TagType {
  public static let pet = TagType.user(
    "pet", cbor: 40_123, yaml: "!pet", content: .init(shapes: .object))
}
```

### Validation

| When | Check |
| --- | --- |
| Plan build | A representation's `type` must be within the selected tag's `content.shapes`; otherwise `PlanError.tagContentMismatch` at first use. Example: `{"type": "string", "tag": 1}` fails. |
| Encode | The writer checks every tagged item against `TagContent`: shape, `format`, byte length, and the `validate` hook. This covers `Value`s written directly, where no plan exists. |
| Decode | Tag validity per RFC 8949 §5.3.2. Content that doesn't match its tag is invalid: `CodingError.invalidTagContent` by default, or the tag is ignored under `TagPolicy.ignoreInvalid`. |

### Tag policy

```swift
public struct TagPolicy: Sendable {
  public var decodeUntagged: Presence = .accept      // .accept, .reject (require the tag)
  public var decodeUnexpected: Handling = .reject    // a tag the plan didn't select: .reject, .ignore
  public var decodeInvalid: Handling = .reject       // content doesn't match its tag
  public var encode: Emission = .asPlanned           // .asPlanned, .omitAll
}
```

### Tags in formats without tags

- **JSON** has no tags.
  - Typed coding never emits a JSON tag convention. A `json` overlay that sets `tag` is a
    `PlanError`.
  - Free-form `Value`s keep the existing `JSONValueWriter.TagShape` conventions as an explicit
    opt-in.
- **`form-urlencoded`** has no tags. Tags are dropped on write; there is nothing to read.
- **XML** (future): to be decided in the SolidXML design.

### Tags as discriminators

In tag-capable formats, a family can be discriminated by tag instead of by property:

```json
"discriminator": { "tag": { "pet": "#/$defs/Pet", "owner": "#/$defs/Owner" } }
```

The decoder reads the tag before the content and dispatches immediately, with no record/replay. In
formats without tags, the property `discriminator` must also be present, or plan building fails
for that format.

### Type-level tags

`@SchemaCodable(tag: .pet)`, or `"tag": "pet"` at the root of a type's schema, tags the type's
whole map: a CBOR tag on the map, or `!pet` on a YAML mapping.

## Swift Spelling

Representation options are a generic `Targeted<Encoding>` value. The same shape is used by every
field type that has representation choices. Each node holds a complete encoding, which compiles to
a complete keyword set at that node, so a Swift value at a node replaces its parent's encoding. The
cascade still decides which node applies to a format: `json` uses `text`, which falls back to `all`.

```swift
public struct Targeted<Encoding: Sendable & Hashable>: Sendable, Hashable {
  public var all: Encoding
  public var text: Encoding?
  public var binary: Encoding?
  public var formats: [FormatID: Encoding]
}

public enum DateTimeEncoding: Sendable, Hashable {
  case rfc3339(fractionalDigits: FractionalDigits = .upTo(9))
  case epoch(Units, as: NumberShape = .integer)
  case httpDate
  indirect case tagged(TagType, DateTimeEncoding)
}
```

In attribute form (see [field options](2026-09-30-solid-coding-design.md#field-options)):

```swift
@Field(.dateTime(.rfc3339()))                                          // everywhere
@Field(.dateTime(.rfc3339(), binary: .epoch(.seconds)))                // binary override
@Field(.dateTime(.rfc3339(), binary: .epoch(.seconds),
                 formats: [.cbor: .tagged(.cbor.epochDateTime, .epoch(.seconds))]))
@Field(.binary(text: .base64url))                                      // bytes: native in binary formats
@Field(.uuid(binary: .bytes, formats: [.cbor: .tagged(.cbor.uuid, .bytes)]))
```

The same rules apply in Swift as in the schema:
- `.tagged(.cbor.epochDateTime, .rfc3339())` is rejected when the macro emits it, as an error at the
  attribute, and again at plan build.
- A tag whose `identities` lack the target format is an error for that format, for example a
  CBOR-only tag in a `text` overlay.

## Testing

- Selector resolution: every combination of `all`/`kind`/`format` entries, per format.
- Every standard registry entry: valid and invalid content in CBOR and YAML, on encode and decode.
- RFC 8949 Appendix A examples that use tags, decoded as `Value` and through typed plans.
- User tags: registry conflicts, range warnings, YAML `tag:` URI validation, and round trips.

## Future: Representation-Specific Assertions

Overlays are limited to representation keywords for now. Encoding complex formats will eventually
need assertions on the wire form itself, for example `minimum: 0` on an epoch-seconds integer, or a
`maxLength` on a base64 text form.

To keep that addition non-breaking:
- **Today:** the Solid meta-schema **rejects** assertion keywords inside `representations`, so no
  schema written now can change meaning later.
- **Later:**
  - Overlay assertions apply to the wire value of that representation, in addition to the base
    schema's assertions.
  - Overlay assertions cascade like representation keywords.
  - The evaluator runs them only when `targetFormat` is set, or for the representation actually
    matched when it is not.

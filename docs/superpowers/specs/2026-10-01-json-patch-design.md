# JSON Patch and JSON Merge Patch

Part of the [SolidCoding design set](2026-09-30-solid-coding-design.md).

## Goal

`SolidData` should provide complete, RFC-conformant implementations of:

- **JSON Patch** ([RFC 6902](https://www.rfc-editor.org/rfc/rfc6902)), `application/json-patch+json`
- **JSON Merge Patch** ([RFC 7396](https://www.rfc-editor.org/rfc/rfc7396)), `application/merge-patch+json`

Both work on `Value`, so they apply to any document in any format. `SolidCoding` builds typed
ergonomics on top of them: generated patch types with `PatchOp` fields, and a type-safe JSON Patch
builder. Sunday's `UpdateOp`/`PatchOp` and the generator's patchable-type output move onto these.

## Foundations

### JSON Pointer mutation

`Value+Pointer` has only a read subscript today. Add the full RFC 6901 surface:

```swift
extension Value {
  public subscript(pointer: Pointer) -> Value? { get }                       // exists
  public mutating func set(_ value: Value, at pointer: Pointer) throws(PointerError)
  public mutating func insert(_ value: Value, at pointer: Pointer) throws(PointerError)   // array insert / "-"
  @discardableResult
  public mutating func remove(at pointer: Pointer) throws(PointerError) -> Value
}

extension Pointer {
  public static let root: Pointer
  public var isRoot: Bool { get }
  public func isProperPrefix(of other: Pointer) -> Bool
  public enum ArrayIndex { case index(Int), end }   // "-" token
}
```

- Array-index tokens follow RFC 6901 §4: no leading zeros, and `-` only where the operation allows
  it.
- Escaping (`~0`, `~1`) already exists.
- `Value` objects may have non-string keys (CBOR, YAML). Pointer tokens address string keys only, so
  a non-string key is not addressable and reports `PointerError.nonStringKey`.

### JSON equality

RFC 6902 §4.6 `test` defines equality: numbers compare by value, objects ignore member order, arrays
compare element-wise, strings compare by code points. `Value`'s `==` is structural: `1` and `1.0`
differ, and object order matters because `Value.Object` is ordered. Add:

```swift
extension Value {
  public func jsonEquals(_ other: Value) -> Bool
}
```

Numbers compare through `BigDecimal`, so integer and float forms of the same value are equal and
there is no `Double` rounding. Tags are compared only when both sides are tagged.

## JSON Patch (RFC 6902)

```swift
public struct JSONPatch: Sendable, Hashable, RandomAccessCollection, ExpressibleByArrayLiteral {
  public var operations: [Operation]

  public enum Operation: Sendable, Hashable {
    case add(path: Pointer, value: Value)
    case remove(path: Pointer)
    case replace(path: Pointer, value: Value)
    case move(from: Pointer, path: Pointer)
    case copy(from: Pointer, path: Pointer)
    case test(path: Pointer, value: Value)
  }

  public func apply(to document: Value) throws(JSONPatchError) -> Value
  public func apply(to document: inout Value) throws(JSONPatchError)    // atomic: unchanged on error

  public init(from source: Value, to target: Value, options: DiffOptions = .default)

  public init(document: Value) throws(JSONPatchError)                    // from the JSON array form
  public var document: Value { get }
}

public struct JSONPatchError: Error, Sendable {
  public var operationIndex: Int
  public var operation: JSONPatch.Operation?
  public var kind: Kind      // invalidDocument, pathNotFound, parentNotFound, indexOutOfRange,
                             // invalidIndex, fromIsProperPrefixOfPath, testFailed(expected:actual:)
}
```

### Conformance rules (RFC 6902 §4 and §5)

| Area | Rule |
| --- | --- |
| Order | Operations apply in order. Each operation sees the previous one's result. |
| Atomicity | All or nothing. Value semantics give this cheaply: work on a copy, assign on success. |
| `add` | Target location: an array index (`0…count`, or `-` to append) or an object member. An existing member is replaced. The parent must exist. Root path `""` replaces the whole document. |
| `remove` | The target must exist. Array elements after it shift left. |
| `replace` | Same as `remove` then `add` at the same path, but the target must exist. |
| `move` | `from` must exist and must not be a proper prefix of `path`. Equivalent to `remove(from)` then `add(path)`. |
| `copy` | `from` must exist. Equivalent to `add(path, value at from)`. |
| `test` | Uses `jsonEquals`. Failure aborts the patch. |
| Document parsing | The top level must be an array of objects with `op` and `path`, plus `value` or `from` as required. Members that do not belong to the operation are ignored (§4). Unknown `op` is an error. Missing `value` is an error, but an explicit `null` value is valid. |

### Diff generation

The RFC does not define how to produce a patch. `init(from:to:options:)` guarantees that applying
the result to `source` gives a value `jsonEquals` to `target`. It also tries to produce a small
patch:

- **Objects.** Recurse into shared keys, `remove` missing keys, `add` new keys.
- **Arrays.** `DiffOptions.arrays` selects one of:
  - `.replaceWhole` (default; always correct and smallest to compute),
  - `.positional` (index-by-index `replace`, then trailing `add`/`remove`),
  - `.longestCommonSubsequence` (Myers diff; emits `add`/`remove`, and `move` when `detectMoves`
    is set).
- **`DiffOptions.emitTests`** adds a `test` before each `replace`/`remove` with the old value. This
  gives optimistic-concurrency patches suitable for HTTP `PATCH` (RFC 5789).

## JSON Merge Patch (RFC 7396)

```swift
public struct MergePatch: Sendable, Hashable {
  public var document: Value                 // any Value; a non-object replaces the target

  public init(_ document: Value)
  public func apply(to target: Value) -> Value
  public func apply(to target: inout Value)

  public init(from source: Value, to target: Value) throws(MergePatchError)   // diff
  public func merged(with later: MergePatch) -> MergePatch                    // compose two patches
}
```

- `apply` implements the §2 algorithm exactly:
  - If the patch is an object, the target becomes an object if it is not one already.
  - Each `null` member removes that key. Every other member is merged recursively.
  - If the patch is not an object, it replaces the target.
- Diffing cannot express "set to `null`" or a partial array change, both inherent limits of RFC 7396
  (§1 and §3). `init(from:to:)` writes arrays as whole replacements. If the target contains a
  `null` member value that differs from the source, it throws `MergePatchError.cannotRepresentNull`
  with the pointer.
- Composition: `a.merged(with: b)` gives a patch equal to applying `a` then `b`, as long as neither
  is a non-object patch at a location the other merges into. Otherwise the later patch wins at that
  location, as in sequential application.

## Typed Ergonomics (SolidCoding)

### `PatchOp`

```swift
public enum PatchOp<Wrapped>: Sendable where Wrapped: Sendable {
  case keep                        // absent from the patch document
  case set(Wrapped)                // member with a value
  case delete                      // member with null
}

public enum UpdateOp<Wrapped>: Sendable where Wrapped: Sendable {
  case keep
  case set(Wrapped)                // for required, non-nullable properties: delete is not representable
}

public enum MergeOp<Patch>: Sendable where Patch: MergePatchable {
  case keep
  case set(Patch.Target)           // replace the whole nested object
  case merge(Patch)                // recursive merge (RFC 7396 object semantics)
  case delete
}
```

`PatchOp` and `UpdateOp` map one-to-one onto the slot states in the
[SolidCoding property slots](2026-09-30-solid-coding-design.md#property-slots), so decoding and
encoding them costs nothing extra.

### Generated merge-patch types

`@SchemaCodable(mergePatch: true)`, or a separate `@MergePatchable`, generates a companion
`Patch` type. Field types come from the schema:

| Property in the target type | Field in `Patch` |
| --- | --- |
| required, non-nullable scalar or array | `UpdateOp<T>` |
| optional or nullable scalar or array | `PatchOp<T>` |
| nested object type `Owner` | `MergeOp<Owner.Patch>` (`delete` only when optional or nullable) |
| map `[String: T]` | `MapPatch<T>` (per-key `PatchOp`, matching RFC 7396's recursive object merge) |
| preserved unknown properties | `[String: PatchOp<Value>]` |

```swift
var patch = Pet.Patch()
patch.name = .set("Rex")
patch.photo = .delete
patch.owner = .merge { $0.email = .set("rex@example.com") }

let updated = try patch.apply(to: pet)           // typed apply, validated against Pet's schema
let doc: MergePatch = patch.mergePatch           // Value-level document
let body = try JSON.encode(patch)                // application/merge-patch+json

let diff = try Pet.Patch(from: old, to: new)     // typed diff
```

- **Patch schema.** Derived from the target schema: every property becomes optional, and `null` is
  allowed where the target property is optional or nullable. Servers decode `Pet.Patch` with full
  validation of the patch document itself.
- **Apply.** `apply(to:)` works field by field, with no `Value` round trip. It then validates the
  result against the target schema's plan, catching cross-field rules such as `dependentRequired`.

### Typed JSON Patch builder

Key paths cannot be split into components at runtime. So the builder uses a generated
`@dynamicMemberLookup` path proxy. The macro emits a per-type table from single-step key paths to
pointer tokens.

```swift
let patch = try JSONPatch.build(for: Pet.self) { pet in
  pet.version.test(3)
  pet.name.replace(with: "Rex")
  pet.tags.append("good")
  pet.tags[0].remove()
  pet.owner.email.replace(with: "rex@example.com")
  pet.photo.move(to: pet.archive.photo)
}

let updated: Pet = try patch.apply(to: pet)       // encode → apply → decode, schema-validated
```

- **Values.** Each value is encoded with the representation that location's plan chooses. A `Date`
  passed for a property stored as epoch milliseconds produces the right number.
- **Paths.** Each proxy step checks the property exists. Array steps support `[i]` and `append`.
  Map steps support `["key"]`.

## Sunday Mapping

| Sunday today | New |
| --- | --- |
| `UpdateOp<T>?` / `PatchOp<T>?` fields on the model type | Generated `Model.Patch` companion with `UpdateOp`/`PatchOp`/`MergeOp` fields |
| `decodeIfExists` / `encodeIfExists` container extensions | Slot states; nothing extra |
| `AnyPatchOp.merge(...)` helpers | `MergeOp.merge` |
| No JSON Patch support | `JSONPatch` plus the typed builder; `MediaType.jsonPatch` is registered |

## Testing

- Vendor the [json-patch-tests](https://github.com/json-patch/json-patch-tests) corpus
  (`tests.json`, `spec_tests.json`) next to the JSON-Schema-Test-Suite and run it with Swift
  Testing.
- Run all RFC 7396 Appendix A examples as tests.
- Property tests:
  - `JSONPatch(from: a, to: b).apply(to: a).jsonEquals(b)`
  - `MergePatch(from: a, to: b).apply(to: a) == b`, when `b` has no `null` members
  - patch composition laws

## Open Questions

1. Should `JSONPatch.apply` accept non-JSON `Value`s (tags, bytes, non-string keys) silently, or
   require an explicit `allowExtendedValues` option, given RFC 6902 is defined over JSON only?
2. `MergeOp.set` vs `.merge` for nested objects: should generated code default to `.merge` when a
   whole nested value is assigned through a convenience setter?

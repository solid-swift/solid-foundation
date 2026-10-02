# Schema Streaming Evaluation and Coding Plans

Part of the [SolidCoding design set](2026-09-30-solid-coding-design.md).

## Goal

`SolidSchema` should be able to evaluate a schema **while events stream past**, and turn a schema
into a **coding plan** that tells a decoder or encoder how each location is represented on the
wire. Together these make the schema the only source of truth for validation and representation:

- Typed `SolidCoding` decoders and encoders evaluate in lockstep with the event stream. Type code
  maps structure only and never spells out constraints.
- A **schema-only adapter** decodes and encodes `Value` with full validation and representation
  normalization and no Swift types at all.
- The existing tree validator becomes a thin wrapper that replays a `Value` as events. This leaves
  one implementation, tested by the JSON-Schema-Test-Suite already vendored in `Tests/SolidSchemaTests`.

## Current State

- `Schema.Builder` compiles a schema `Value` into a graph of sub-schemas and `KeywordBehavior`s.
  The schema is already "compiled"; nothing re-parses keywords at validation time.
- Every behavior evaluates a complete instance: `apply(instance: Value, context: inout
  Validator.Context) -> Validation`. Applicators recurse into child `Value`s.
- `Schema.StreamValidator` accepts `EmitEvent`s but, per its own doc comment, "buffers a full value
  before validating."
- The Solid vocabulary defines `units`, `bitWidth` (annotations), `minSize`/`maxSize` (assertions),
  and reserves `encoding`.
- `SolidSchema` imports `SolidJSON` in exactly two places. Meta-schemas are Swift literals, so they
  don't need it.
  - `Contents/JSONContentMediaTypeType.swift`: `contentMediaType: application/json` checks that a
    string parses as JSON. It is registered unconditionally in `ContentMediaTypeTypes.init()`.
  - `Containers/LocalDirectorySchemaContainer.swift`: loads `$ref`'d schema files from a
    directory, as JSON only.
- `contentSchema` is annotation-only: content is never parsed and evaluated against it.

## Streaming Evaluation

### Model

An `Evaluator` consumes the instance as a sequence of events. It keeps a stack of **frames**, one per
instance depth. Each frame holds the **active evaluations** at that location. An evaluation is a
(sub-schema, dynamic scope, instance location) triple plus per-keyword state.

```swift
extension Schema {
  public struct Evaluator: ~Copyable {
    public init(schema: Schema, options: Schema.Options = .default, output: Validator.OutputFormat = .basic)

    public mutating func consume(_ event: borrowing EvaluationEvent) throws(EvaluationError)
    public mutating func finish() throws(EvaluationError) -> Validator.Result

    /// Validity known so far for the value currently being closed (used by typed decoders).
    public var lastCompletedValidity: Validity { get }
  }

  public enum EvaluationEvent {           // scalars are already materialized or typed
    case beginObject, key(KeyRef), endObject
    case beginArray, endArray
    case scalar(ScalarValue)               // null/bool/int/float/decimal/string/bytes (borrowed)
    case tag(UInt64)
  }
}
```

When a container starts, each active evaluation asks its applicator keywords which sub-schemas
apply to each child as it appears. The child frame starts with exactly those evaluations. When a
child ends, its results (validity and annotations) go back to the keywords that spawned it. When
the container ends, each keyword produces its result.

### Keyword protocol

Add a streaming protocol next to `KeywordBehavior`. Each behavior adopts it; the tree method
becomes a default implementation that replays a `Value` as events.

```swift
extension Schema {
  public protocol StreamingKeywordBehavior: KeywordBehavior {
    associatedtype State = Void

    /// Called when the instance at this location begins. Return nil to skip (wrong instance type).
    func begin(_ kind: InstanceKind, context: inout EvaluationContext) -> State?

    /// Scalars: assert directly.
    func scalar(_ value: borrowing ScalarValue, state: inout State, context: inout EvaluationContext) -> Validation

    /// Containers: sub-schemas to apply to the next child (applicators only).
    func children(for child: ChildLocation, state: inout State, context: inout EvaluationContext) -> ChildSchemas

    /// Results of a child this keyword spawned.
    func childFinished(_ child: ChildLocation, result: ChildResult, state: inout State)

    /// Instance ended: final validation and annotation.
    func end(state: consuming State, context: inout EvaluationContext) -> Validation
  }
}
```

### Hard keywords

| Keyword | Streaming approach |
| --- | --- |
| `allOf`, `anyOf`, `oneOf`, `not`, `$ref`, `$dynamicRef` | All branches are evaluated concurrently in the same frame; results combine at `end`. `$dynamicRef` resolves against the dynamic scope carried by each evaluation. |
| `if` / `then` / `else` | `if`, `then`, and `else` all run speculatively; `end` picks the result. |
| `properties`, `patternProperties`, `additionalProperties`, `propertyNames` | Decided per key as it arrives. `propertyNames` evaluates the key scalar. |
| `prefixItems`, `items`, `contains`, `minContains`, `maxContains` | Decided per index; `contains` counts matches. |
| `dependentRequired`, `dependentSchemas`, `required` | Key set collected per frame; checked at `end`. `dependentSchemas` runs speculatively on the object and is kept only if its trigger key appeared. |
| `unevaluatedProperties`, `unevaluatedItems` | Their sub-schema runs **speculatively on every child**. At `end`, results are kept only for children that no adjacent keyword evaluated, using the annotations collected in the frame. |
| `const`, `enum` (container values), `uniqueItems` | Need the whole value. The frame captures the subtree as a `Value` with `EmitEventDecoder` only when one of these keywords is active at that location. |
| `contentEncoding`, `contentMediaType`, `contentSchema` | Annotations by default. When `Options.validateContent` is on, the string is decoded and evaluated as a nested document at `end`. |
| `format` | Assertion or annotation per `Options.formatAssertion`; checked on the scalar. |

Speculative evaluation is bounded by schema shape, not by data size. Two kinds of pruning cut it
back:

- **Flag output with no `unevaluated*` in scope.** Failed branches are dropped as soon as they fail.
- **`oneOf` that can tell its branches apart.** A discriminator keyword or disjoint instance types
  prune branches at the first event.

### Tree validation becomes replay

`Schema.Validator.validate(instance:)` drives the evaluator with `ValueEmitEventCursor`. The
tree-based `apply(instance:)` implementations remain only until the streaming implementation passes
the 2020-12 JSON-Schema-Test-Suite groups that `SolidSchemaTests` already runs, including the optional and format groups. After that they are
deleted. `Schema.StreamValidator` becomes a typealias for `Evaluator`.

## Coding Plans

A typed decoder needs to know, at each location, how the value is represented, not just whether it
is valid. A **coding plan** is a compiled projection of the schema for that purpose.

```swift
extension Schema {
  public final class CodingPlan: Sendable {            // immutable graph, cached per (schema, root, format)
    public static func build(for schema: Schema, at pointer: Pointer = .root, format: FormatID,
                             options: CodingPlan.Options = .default) throws(PlanError) -> CodingPlan
    public var root: CodingPlan.Node { get }
  }
}

extension Schema.CodingPlan {
  public enum Node: Sendable {
    case scalar(ScalarPlan)            // shapes, codec selection, constraints
    case object(ObjectPlan)            // key table, required, defaults, unknown policy, child plans
    case array(ArrayPlan)              // prefix plans, item plan, count constraints
    case map(MapPlan)                  // additionalProperties plan, propertyNames constraints
    case union(UnionPlan)              // discriminator table or disjoint-shape dispatch
    case any(AnyPlan)                  // free-form: capture as Value, evaluate with Evaluator
  }

  public struct ScalarPlan: Sendable {
    public var shapes: ShapeSet                    // string/integer/number/bytes/bool/null, ordered
    public var semantic: SemanticType               // from format: dateTime, uuid, uri, decimal, …
    public var units: Units?                        // s/ms/us/ns/d
    public var textEncoding: BaseEncoding?          // from `encoding`
    public var width: IntegerWidth?                 // from bitWidth + signed
    public var constraints: ScalarConstraints       // min/max/multipleOf/length/pattern/format/enum/const
    public var nullable: Bool
    public var tag: TagType?                        // selected for this format, validated against shapes
  }

  public struct ObjectPlan: Sendable {
    public var keys: KeyTable                       // precomputed UTF-8 match table → property index
    public var properties: [PropertyPlan]           // name, node, required, default
    public var unknown: UnknownPropertyPolicy       // preserve / skip / reject / schema(Node)
    public var patterns: [(SchemaPattern, Node)]
    public var residual: Schema.Evaluator.Seed?     // keywords the plan cannot express inline
  }
}
```

### Building a plan

Plan building **resolves**:
- `$ref`s, and `$dynamicRef`s within the static scope.
- `allOf`, merged by intersecting constraints. Representation keywords must agree.
- `type` lists, into ordered shape sets.

Plan building **classifies** `anyOf`/`oneOf`. Each becomes either:
- a discriminator dispatch, or
- a disjoint-shape dispatch (string vs object vs array), or
- a **record/replay** union that tries each branch in order.

Plan building **records** a **residual** for what it cannot express inline (`if`/`then`/`else`,
`dependentSchemas`, `unevaluated*`, `const`/`enum` on containers, `uniqueItems` on objects). The
typed reader feeds the residual's location to a full `Evaluator`. Nodes with an empty residual
validate entirely through inline checks, which is the common case for API models.

### Codability analysis

Plan building fails with a `PlanError` that points at the schema location when a location is
valid JSON Schema but has no single typed representation. Examples:
- `oneOf` across object shapes with neither a discriminator nor distinct required keys
- `allOf` branches that disagree on `format`
- `if`/`then` that changes `type`

These locations can still be decoded as `Value` (see below). The Sunday generator runs the same
analysis at generation time and reports these as generator diagnostics.

### Binding a Swift type to a plan

Typed decoders bind their stored properties to an `ObjectPlan` once, cached in a `static let`:

```swift
public struct TypeBinding<T>: Sendable {
  public init(_ type: T.Type, plan: Schema.CodingPlan.Node, fields: [FieldDescriptor]) throws(BindingError)
  public func slot(for key: borrowing KeyRef) -> Int?         // wire key → Swift field index
}

public struct FieldDescriptor: Sendable {
  public var wireName: String
  public var swiftType: Any.Type
  public var kind: FieldKind      // .scalar(ScalarKind), .object, .array, .map, .value, .patch, …
}
```

Binding checks compatibility and fails at first use with a precise message. Examples:
- `Int16` bound to a location whose `maximum` exceeds `Int16.max`
- a non-optional field whose property is neither required nor defaulted
- `OffsetDateTime` bound to a location whose `format` is `uuid`

The macro also emits a test helper that forces every binding, so mistakes surface in unit tests and
not in production.

### Which schema governs a nested type

A nested type is decoded at a location inside its container's plan. **The containing location
governs.** It may `$ref` the nested type's schema and add constraints with `allOf`. The nested
type's own `static var schema` is used only when it is the root of a decode, or when the containing
location is the `true` schema. When a location `$ref`s a schema `$id` that a type declares,
binding uses that type's field descriptors. This lets one Swift type appear at several locations
with different constraints.

## Schema-Only Adapter

A schema plus events in, a validated and normalized `Value` out, with no Swift types and no
generated code:

```swift
extension Schema {
  public struct ValueCoder: Sendable {
    public init(schema: Schema, options: ValueCoder.Options = .default) throws(PlanError)

    public func decode<R: FormatEventReader & ~Copyable>(from reader: inout R) throws(CodingError) -> Value
    public func encode<W: FormatEventWriter>(_ value: Value, to writer: inout W) throws(CodingError)

    public struct Options: Sendable {
      public var normalization: Normalization = .none   // .none, .canonical
      public var applyDefaults: Bool = false
      public var unknownProperties: UnknownPropertyPolicy? = nil   // override the schema's policy
    }
  }
}
```

- `.canonical` normalization uses each location's plan to put scalars in canonical `Value` form.
  Dates become CBOR-style tagged values (tag 0/1), text-encoded bytes become `.bytes`, and decimal
  strings become numbers. The same `Value` can then be written in another format: JSON in, CBOR out.
- Encoding does the reverse: each location's preferred shape is chosen from the plan.
- Locations that failed codability analysis are captured as-is and only validated.

Typical uses: gateways and proxies, Sunday server request validation, schema-driven tools, and
decoding free-form fields that carry a schema.

## Performance

- Evaluations, frames, and keyword state are value types in arena-backed stacks reused across
  documents. A steady-state decode allocates nothing in the evaluator.
- Key tables are built once per plan. They are perfect-hash or length-then-bytes tables over UTF-8.
- Patterns compile once per plan into stdlib `Regex`. ECMA-262 constructs the stdlib cannot express
  are a `PlanError`, not a silent mismatch.
- Benchmarks: tree validation through replay versus the current tree validator must stay within
  10% before the old implementation is removed.

## Phasing

1. `Evaluator` with all 2020-12 keywords. The tree validator becomes replay. The test suite passes.
2. Solid vocabulary meta-schema and keyword behaviors (see the vocabulary in the
   [SolidCoding design](2026-09-30-solid-coding-design.md#solid-coding-vocabulary)).
3. `CodingPlan`, codability analysis, `TypeBinding`.
4. `Schema.ValueCoder`.

## Format-Agnostic Content and Schema Resources

Both JSON-specific uses become format-agnostic. `SolidSchema` then depends only on SolidData's
`Format` abstraction and drops `SolidJSON`.

```swift
// SolidData: formats describe themselves and can read a Value
public protocol Format: Sendable {
  var id: FormatID { get }
  var kind: FormatKind { get }
  var mediaTypes: [String] { get }          // "application/json", "application/yaml", "application/cbor", …
  var fileExtensions: [String] { get }      // "json"; "yaml", "yml"; "cbor"
  func readValue(from data: Data) throws -> Value
  func supports(type: ValueType) -> Bool
}

// SolidSchema
extension Schema.Options {
  public var formats: [any Format]          // empty by default in SolidSchema
  public var validateContent: Bool          // contentEncoding → contentMediaType → contentSchema
}
```

- **Content media types.** `FormatContentMediaType(format:)` replaces `JSONContentMediaTypeType`.
  `ContentMediaTypeTypes` registers one per media type of each format in `Options.formats`. So
  `application/yaml` and `application/cbor` content validate the same way JSON does.
- **`contentSchema`.** With `validateContent` on:
  - the string is decoded per `contentEncoding` (RFC 4648 codecs from SolidCore);
  - it is parsed with the format matching `contentMediaType`;
  - the result is evaluated against `contentSchema` as a nested document, with its errors nested
    under the string's location.

  Without a matching format, `contentSchema` stays an annotation (JSON Schema 2020-12 §8 makes
  content validation opt-in).
- **Schema resources.** `LocalDirectorySchemaContainer(directory:formats:)` chooses a reader by file
  extension, so schema directories can mix `.json` and `.yaml`.
- **Default wiring.**
  - `SolidCoding`, and the umbrella `Solid` module, provide `Schema.Options.standard` with the JSON,
    YAML, and CBOR formats.
  - Code that uses `SolidSchema` alone passes the formats it links.
  - `SolidSchemaTests` adds `SolidJSON` as a test dependency.
  - Behaviour change: plain `SolidSchema` no longer checks `application/json` content implicitly.

## Format-Targeted Representations

`representations` overlays and `tag` are resolved **when the plan is built**, for the plan's
`FormatID`. Keywords cascade from `any` through the format's kind (and any parent formats) down to the format itself, per keyword. So each plan node holds
exactly one representation, and readers never re-resolve per value. See the
[representations and tags design](2026-10-01-representations-and-tags-design.md).

The evaluator takes `Schema.Options.targetFormat`:
- When set, it applies the keywords resolved for that format.
- When `nil`, a value is valid under the base or any overlay.

Plan building also enforces tag/shape compatibility (`PlanError.tagContentMismatch`) and rejects
tags in formats without tags.

## Open Questions

1. Should `validateContent` default to on for the Solid dialect, while staying off for plain
   2020-12 schemas? Typed decoders of embedded documents would benefit.

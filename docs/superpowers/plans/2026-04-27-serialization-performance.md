# Serialization Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove structural performance costs introduced or exposed by the push-parser / zero-copy refactor while preserving the current public event API and green test baseline.

**Architecture:** Keep JSON, CBOR, and YAML on the existing `FormatEventReader -> BufferedStreamDecoder -> ParseEvent` pipeline. Improve hot shared primitives first (`ParseBuffer.Region`, `ScalarRef`, pending queues), then update format-specific readers/resolvers to use those primitives without changing observable event streams.

**Tech Stack:** Swift 6.2, SwiftPM, `Foundation.Data`, `Synchronization.Mutex`, `InlineArray`, `ContiguousArray`, `OutputSpan`, SolidData parse/emit events.

---

## Baseline and Guardrails

- Preserve public API direction: reading emits `ParseEvent`, writing consumes `EmitEvent`, and document framing remains `FormatDocumentEvent`.
- Preserve compatibility properties: `ScalarRef.rawData`, `ParseBuffer.Region.data`, `ValueEvent`, `ValueEventEncoder`, and `ValueEventDecoder` aliases.
- Use `env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox` for verification.
- Treat the current full-suite green state as a compatibility constraint.
- Do not rewrite YAML parsing wholesale in this plan; focus only on concrete performance improvements that retain test parity.

## File Structure

- Modify `Sources/Solid/Data/Format/ParseBuffer.swift`
  - Store retained segment and range directly in `ParseBuffer.Region`.
  - Add region/span-style access without first materializing a `Data` slice.
  - Add byte advancing and region-reading helpers.

- Modify `Sources/Solid/Data/Value/ScalarRef.swift`
  - Make buffered scalar storage inline in `ScalarRef`.
  - Allocate cache storage lazily on first materialization only.
  - Keep `rawData` and cached materialization behavior source-compatible.

- Modify `Sources/Solid/JSON/JSONScalarResolver.swift`
  - Add region-aware fast paths, including no-escape JSON string decoding.

- Modify `Sources/Solid/CBOR/CBOREventReader.swift`
  - Use `ParseBuffer.advance(count:)` / region-reading helpers instead of `readBytes(count:)` when only advancing.

- Modify `Sources/Solid/CBOR/CBORScalarResolver.swift`
  - Decode integer/float payloads from region bytes without intermediate `Data.dropFirst()` copies.

- Modify `Sources/Solid/YAML/YAMLTokenizer.swift`
  - Replace `pendingTokens.removeFirst()` with indexed queue semantics.
  - Reduce obvious `Array(lines)` conversions in block scalar joins.

- Modify `Sources/Solid/Data/Format/FormatStreamReaderDriver.swift`
  - Add single-consumer protection for `next()`.

- Modify `Sources/Solid/Data/Format/FormatStreamWriterDriver.swift`
  - Add single-consumer protection for `write(_:)` and `finish()`.

- Modify tests:
  - `Tests/SolidDataTests/ScalarRefTests.swift`
  - `Tests/SolidDataTests/ParseBufferTests.swift` or create it if absent.
  - `Tests/SolidJSONTests/JSONZeroCopyTests.swift`
  - `Tests/SolidCBORTests/CBORZeroCopyTests.swift`
  - `Tests/SolidYAMLTests/YAMLTokenizerTests.swift`
  - Add driver concurrency tests under `Tests/SolidDataTests/FormatStreamDriverTests.swift` if no equivalent exists.

---

### Task 1: Lock Current Performance Baseline

**Files:**
- No source changes.

- [ ] **Step 1: Run targeted serialization suites**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidData
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidJSON
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidCBOR
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidYAML
```

Expected: all targeted suites pass. If any suite fails, stop and fix the baseline before continuing.

- [ ] **Step 2: Run full suite**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox
```

Expected: full suite passes.

- [ ] **Step 3: Record baseline notes**

Add a short implementation note to the execution thread with:

```text
Baseline passed:
- SolidData
- SolidJSON
- SolidCBOR
- SolidYAML
- Full suite
```

Do not commit unless the project workflow requires commits.

---

### Task 2: Make ParseBuffer.Region Truly Retained-Range Based

**Files:**
- Modify: `Sources/Solid/Data/Format/ParseBuffer.swift`
- Test: `Tests/SolidDataTests/ParseBufferTests.swift`

- [ ] **Step 1: Add failing tests for region storage behavior**

Create `Tests/SolidDataTests/ParseBufferTests.swift` if it does not exist. Add tests equivalent to:

```swift
import Foundation
import SolidData
import Testing

@Suite("ParseBuffer")
struct ParseBufferTests {

  @Test("Same-segment regions preserve metadata and bytes")
  func sameSegmentRegionMetadata() throws {
    var buffer = ParseBuffer()
    buffer.append(Data("abcdef".utf8))

    _ = try buffer.readByte()
    let start = buffer.mark()
    _ = try buffer.readBytes(count: 3)
    let region = buffer.region(from: start, to: buffer.mark())

    #expect(region.isCopied == false)
    #expect(region.segmentIndex != nil)
    #expect(region.segmentRange == 1..<4)
    #expect(region.bytes == Data("bcd".utf8))
    #expect(try region.string() == "bcd")
  }

  @Test("Cross-segment regions copy once and preserve bytes")
  func crossSegmentRegionCopies() throws {
    var buffer = ParseBuffer()
    buffer.append(Data("ab".utf8))
    buffer.append(Data("cd".utf8))

    let start = buffer.mark()
    _ = try buffer.readBytes(count: 4)
    let region = buffer.region(from: start, to: buffer.mark())

    #expect(region.isCopied == true)
    #expect(region.segmentIndex == nil)
    #expect(region.segmentRange == nil)
    #expect(region.bytes == Data("abcd".utf8))
  }

  @Test("Advance consumes bytes without forcing region materialization")
  func advanceConsumesBytes() throws {
    var buffer = ParseBuffer()
    buffer.append(Data("abcdef".utf8))

    let start = buffer.mark()
    try buffer.advance(count: 4)
    let region = buffer.region(from: start, to: buffer.mark())

    #expect(region.bytes == Data("abcd".utf8))
    #expect(try buffer.readByte() == UInt8(ascii: "e"))
  }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter ParseBufferTests
```

Expected: fails because `advance(count:)` is missing. If tests fail only due to imports/module names, adjust imports to match nearby SolidData tests.

- [ ] **Step 3: Change Region storage**

In `ParseBuffer.Region`, replace storage that stores a ready-made `Data` slice for retained regions with storage that stores the parent segment and range:

```swift
private enum Storage: Sendable {
  case retained(segment: Data, segmentIndex: Int?, segmentRange: Range<Int>)
  case copied(Data)
}
```

Keep compatibility properties:

```swift
public var data: Data { bytes }

public var bytes: Data {
  switch storage {
  case .retained(let segment, _, let range):
    return ParseBuffer.makeNoCopySlice(from: segment, range: range)
  case .copied(let data):
    return data
  }
}
```

Update `segmentIndex`, `segmentRange`, `isCopied`, and initializers accordingly:

```swift
public init(data: Data) {
  self.storage = .retained(segment: data, segmentIndex: nil, segmentRange: 0..<data.count)
}

init(segment: Data, segmentIndex: Int, segmentRange: Range<Int>) {
  self.storage = .retained(segment: segment, segmentIndex: segmentIndex, segmentRange: segmentRange)
}

init(copied data: Data) {
  self.storage = .copied(data)
}
```

- [ ] **Step 4: Make withUnsafeBytes avoid bytes materialization**

Update `Region.withUnsafeBytes`:

```swift
public func withUnsafeBytes<R>(
  _ body: (UnsafeRawBufferPointer) throws -> R
) rethrows -> R {
  switch storage {
  case .retained(let segment, _, let range):
    return try segment.withUnsafeBytes { rawBuffer in
      guard let base = rawBuffer.baseAddress else {
        return try body(UnsafeRawBufferPointer(start: nil, count: 0))
      }
      return try body(UnsafeRawBufferPointer(
        start: base.advanced(by: range.lowerBound),
        count: range.count
      ))
    }
  case .copied(let data):
    return try data.withUnsafeBytes(body)
  }
}
```

- [ ] **Step 5: Add advance and region-reading helpers**

Add to `ParseBuffer`:

```swift
public mutating func advance(count: Int) throws {
  guard count >= 0 else { return }
  guard hasAvailable(count) else { throw ParseBufferError.unexpectedEnd }

  var remaining = count
  while remaining > 0 {
    guard let current = ensureCurrentSegment() else {
      throw ParseBufferError.unexpectedEnd
    }
    let available = current.count - readOffset
    let take = min(available, remaining)
    readOffset += take
    remaining -= take
  }
}

public mutating func readRegion(count: Int) throws -> Region {
  let start = mark()
  try advance(count: count)
  return region(from: start, to: mark())
}
```

- [ ] **Step 6: Update region(from:to:) same-segment path**

Update the same-segment branch:

```swift
return Region(
  segment: segment,
  segmentIndex: start.segmentIndex,
  segmentRange: range
)
```

Leave cross-segment behavior copying into a contiguous `Data`.

- [ ] **Step 7: Run ParseBuffer tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter ParseBufferTests
```

Expected: pass.

- [ ] **Step 8: Run SolidData**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidData
```

Expected: pass.

---

### Task 3: Remove Per-Scalar Box and Mutex Allocation Before Materialization

**Files:**
- Modify: `Sources/Solid/Data/Value/ScalarRef.swift`
- Test: `Tests/SolidDataTests/ScalarRefTests.swift`

- [ ] **Step 1: Add tests that preserve public behavior**

In `ScalarRefTests`, add behavior tests:

```swift
@Test("Buffered ScalarRef exposes raw data before materialization")
func bufferedScalarRefRawDataBeforeMaterialization() throws {
  let region = ParseBuffer.Region(data: Data("123".utf8))
  let ref = ScalarRef(kind: .integer, region: region)

  #expect(ref.kind == .integer)
  #expect(ref.rawData == Data("123".utf8))
}

@Test("Buffered ScalarRef caches materialization")
func bufferedScalarRefCachesMaterialization() throws {
  struct CountingResolver: ScalarResolver {
    final class Counter: @unchecked Sendable {
      var count = 0
    }

    let counter: Counter

    func resolve(_ data: Data, kind: ScalarRef.Kind) throws -> Value {
      counter.count += 1
      return .string(String(decoding: data, as: UTF8.self))
    }
  }

  let counter = CountingResolver.Counter()
  let ref = ScalarRef(kind: .string, region: ParseBuffer.Region(data: Data("abc".utf8)))
  let resolver = CountingResolver(counter: counter)

  #expect(try ref.materialize(using: resolver) == .string("abc"))
  #expect(try ref.materialize(using: resolver) == .string("abc"))
  #expect(counter.count == 1)
}
```

If the existing tests already cover this behavior, keep the existing tests and use them as the safety net.

- [ ] **Step 2: Run ScalarRef tests before implementation**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter ScalarRefTests
```

Expected: pass on behavior. These tests are regression guards rather than expected failures.

- [ ] **Step 3: Replace eager Box with inline storage and lazy cache**

Refactor `ScalarRef` to use inline storage:

```swift
private enum Storage: Sendable {
  case buffered(ParseBuffer.Region)
  case materialized(Value)
}

private final class CacheBox: @unchecked Sendable {
  let cache = Mutex<Value?>(nil)
}

private let storage: Storage
private let cacheBox: CacheBox?
```

Update initializers:

```swift
public init(kind: Kind, region: ParseBuffer.Region) {
  self.kind = kind
  self.storage = .buffered(region)
  self.cacheBox = CacheBox()
}

public init(kind: Kind, value: Value) {
  self.kind = kind
  self.storage = .materialized(value)
  self.cacheBox = nil
}
```

This still allocates a `CacheBox`; do not stop here.

- [ ] **Step 4: Make cache allocation lazy**

Because `ScalarRef` is a `Sendable` value type with immutable public behavior, use a private reference only for lazily initialized cache state:

```swift
private final class LazyCache: @unchecked Sendable {
  private let state = Mutex<Value?>(nil)

  func value(
    load: () throws -> Value
  ) throws -> Value {
    try state.withLock { cached in
      if let cached { return cached }
      let value = try load()
      cached = value
      return value
    }
  }
}
```

Then choose one of these two implementation strategies after checking compiler constraints:

1. Preferred: store `private let cache: LazyCache?` only for buffered values and accept one small reference allocation, but remove the old `Box` that wrapped both storage and cache.
2. If profiling shows even that allocation matters: store `private let cache: ManagedAtomicLazyReference<LazyCache>` only if the project already has an atomic dependency. Do not add a new package dependency in this task.

The minimum acceptable change for this task is eliminating the old `Box(storage:)` allocation that also boxed pre-materialized values. Pre-materialized `.null` and `.bool` must remain allocation-free.

- [ ] **Step 5: Update rawData and materialize**

Implement:

```swift
public var rawData: Data? {
  if case .buffered(let region) = storage {
    return region.bytes
  }
  return nil
}

public func materialize(using resolver: some ScalarResolver) throws -> Value {
  switch storage {
  case .materialized(let value):
    return value
  case .buffered(let region):
    guard let cache else {
      if let regionResolver = resolver as? any RegionScalarResolver {
        return try regionResolver.resolve(region, kind: kind)
      }
      return try resolver.resolve(region.bytes, kind: kind)
    }
    return try cache.value {
      if let regionResolver = resolver as? any RegionScalarResolver {
        return try regionResolver.resolve(region, kind: kind)
      }
      return try resolver.resolve(region.bytes, kind: kind)
    }
  }
}
```

Adjust names to match the final chosen storage fields.

- [ ] **Step 6: Run ScalarRef and SolidData tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter ScalarRefTests
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidData
```

Expected: pass.

---

### Task 4: Route CBOR Reader and Resolver Through Region/Advance APIs

**Files:**
- Modify: `Sources/Solid/CBOR/CBOREventReader.swift`
- Modify: `Sources/Solid/CBOR/CBORScalarResolver.swift`
- Test: `Tests/SolidCBORTests/CBORZeroCopyTests.swift`

- [ ] **Step 1: Add CBOR zero-copy regression tests**

In `CBORZeroCopyTests`, add or verify tests for:

```swift
@Test("Definite byte string exposes payload region")
func byteStringPayloadRegion() throws {
  var reader = CBOREventReader()
  reader.feedInput(Data([0x43, 0x01, 0x02, 0x03]), isFinal: true)

  guard case .scalar(let ref)? = try reader.readEvent() else {
    Issue.record("Expected scalar")
    return
  }

  #expect(ref.kind == .bytes)
  #expect(ref.rawData == Data([0x01, 0x02, 0x03]))
}

@Test("Float region includes init byte and payload")
func floatRegionIncludesHeader() throws {
  var reader = CBOREventReader()
  reader.feedInput(Data([0xFA, 0x3F, 0x80, 0x00, 0x00]), isFinal: true)

  guard case .scalar(let ref)? = try reader.readEvent() else {
    Issue.record("Expected scalar")
    return
  }

  #expect(ref.kind == .float)
  #expect(ref.rawData == Data([0xFA, 0x3F, 0x80, 0x00, 0x00]))
  #expect(try ref.materialize(using: CBORScalarResolver()) == .number(Float32(1.0)))
}
```

- [ ] **Step 2: Replace discarded readBytes calls**

In `CBOREventReader.parseNextItem()`, replace patterns like:

```swift
let payloadStart = buffer.mark()
_ = try readBytes(count: numBytes)
let region = buffer.region(from: payloadStart, to: buffer.mark())
```

with:

```swift
let region = try readRegion(count: numBytes)
```

For floats, preserve `itemStart`:

```swift
try advance(count: 4)
let region = buffer.region(from: itemStart, to: buffer.mark())
```

- [ ] **Step 3: Add local wrappers**

Add wrappers near `readBytes(count:)`:

```swift
private mutating func advance(count: Int) throws {
  do {
    try buffer.advance(count: count)
  } catch ParseBufferError.unexpectedEnd {
    throw CBOR.Error.unexpectedEndOfStream
  }
}

private mutating func readRegion(count: Int) throws -> ParseBuffer.Region {
  do {
    return try buffer.readRegion(count: count)
  } catch ParseBufferError.unexpectedEnd {
    throw CBOR.Error.unexpectedEndOfStream
  }
}
```

- [ ] **Step 4: Update CBORScalarResolver to avoid Data.dropFirst**

Replace `let payload = data.dropFirst()` based decoding with region byte pointer decoding:

```swift
private func resolveInteger(_ region: ParseBuffer.Region) throws -> Value {
  try region.withUnsafeBytes { raw in
    guard raw.count >= 1, let base = raw.baseAddress else {
      throw CBOR.Error.invalidItemType
    }
    let initByte = base.load(as: UInt8.self)
    // Decode additional bytes from base.advanced(by: 1) with loadUnaligned.
  }
}
```

Keep `resolve(_ data: Data, kind:)` as the compatibility implementation and make `resolve(_ region:kind:)` call the new region helpers for `.integer` and `.float`.

- [ ] **Step 5: Run CBOR tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter CBORZeroCopyTests
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidCBOR
```

Expected: pass.

---

### Task 5: Add JSON Region Fast Paths

**Files:**
- Modify: `Sources/Solid/JSON/JSONScalarResolver.swift`
- Test: `Tests/SolidJSONTests/JSONZeroCopyTests.swift`

- [ ] **Step 1: Add no-escape JSON string test**

In `JSONZeroCopyTests`, add:

```swift
@Test("JSON string without escapes materializes directly")
func jsonStringWithoutEscapesMaterializes() throws {
  let region = ParseBuffer.Region(data: Data("hello".utf8))
  let ref = ScalarRef(kind: .string, region: region)

  #expect(try ref.materialize(using: JSONScalarResolver()) == .string("hello"))
}
```

- [ ] **Step 2: Add escaped JSON string regression test**

Add:

```swift
@Test("JSON escaped string still unescapes")
func jsonEscapedStringStillUnescapes() throws {
  let region = ParseBuffer.Region(data: Data(#"hello\nworld"#.utf8))
  let ref = ScalarRef(kind: .string, region: region)

  #expect(try ref.materialize(using: JSONScalarResolver()) == .string("hello\nworld"))
}
```

- [ ] **Step 3: Implement region-aware resolve**

Change `JSONScalarResolver.resolve(_ region:kind:)`:

```swift
public func resolve(_ region: ParseBuffer.Region, kind: ScalarRef.Kind) throws -> Value {
  switch kind {
  case .string:
    if !containsBackslash(region) {
      return .string(try region.string())
    }
    return .string(try resolveString(region))
  case .integer:
    return resolveInteger(region)
  case .float, .number:
    return resolveNumber(region)
  default:
    return try resolve(region.bytes, kind: kind)
  }
}
```

Add helpers:

```swift
private func containsBackslash(_ region: ParseBuffer.Region) -> Bool {
  region.withUnsafeBytes { raw in
    for byte in raw where byte == UInt8(ascii: "\\") {
      return true
    }
    return false
  }
}
```

If generic closure return inference fails, write the loop using an explicit `var found = false`.

- [ ] **Step 4: Add region overloads for number parsing**

Add:

```swift
private func resolveInteger(_ region: ParseBuffer.Region) -> Value {
  region.withUnsafeBytes { rawBuffer in
    let utf8 = rawBuffer.bindMemory(to: UInt8.self)
    return resolveIntegerBytes(utf8, fallback: region.bytes)
  }
}
```

Extract the existing integer loop into:

```swift
private func resolveIntegerBytes(
  _ utf8: UnsafeBufferPointer<UInt8>,
  fallback data: Data
) -> Value {
  // Move the existing resolveInteger loop here.
}
```

Keep `resolveInteger(_ data: Data)` by calling `data.withUnsafeBytes`.

- [ ] **Step 5: Run JSON tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter JSONZeroCopyTests
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidJSON
```

Expected: pass.

---

### Task 6: Replace YAML pendingTokens.removeFirst With Indexed Queue

**Files:**
- Modify: `Sources/Solid/YAML/YAMLTokenizer.swift`
- Test: `Tests/SolidYAMLTests/YAMLTokenizerTests.swift`

- [ ] **Step 1: Add burst-token regression test**

In `YAMLTokenizerTests`, add a test that forces one line to enqueue many tokens:

```swift
@Test("Flow mapping burst tokens drain in order")
func flowMappingBurstTokensDrainInOrder() throws {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data("{a: 1, b: [2, 3], c: {d: 4}}\n".utf8), isFinal: true)

  var tokens: [YAMLRawToken] = []
  while let token = try tokenizer.readToken() {
    tokens.append(token)
  }

  #expect(tokens.count > 8)
  guard case .documentStart = tokens.first else {
    Issue.record("Expected document start")
    return
  }
  guard case .documentEnd = tokens.last else {
    Issue.record("Expected document end")
    return
  }
}
```

Adjust visibility if tests already use package/internal access helpers.

- [ ] **Step 2: Add pending token index**

In `YAMLTokenizer`, change:

```swift
private var pendingTokens: ContiguousArray<YAMLRawToken> = []
```

to:

```swift
private var pendingTokens: ContiguousArray<YAMLRawToken> = []
private var pendingTokenIndex = 0
```

- [ ] **Step 3: Replace readToken removal**

Replace:

```swift
return pendingTokens.removeFirst()
```

with:

```swift
let token = pendingTokens[pendingTokenIndex]
pendingTokenIndex += 1
if pendingTokenIndex == pendingTokens.count {
  pendingTokens.removeAll(keepingCapacity: true)
  pendingTokenIndex = 0
}
return token
```

- [ ] **Step 4: Update pendingTokens.isEmpty checks**

Add:

```swift
private var hasPendingTokens: Bool {
  pendingTokenIndex < pendingTokens.count
}
```

Change loops that test `pendingTokens.isEmpty` after partial drain to use `!hasPendingTokens` where needed.

The top of `readToken()` should become:

```swift
mutating func readToken() throws -> YAMLRawToken? {
  while !hasPendingTokens {
    guard !finished else { return nil }
    // existing token production loop
  }

  let token = pendingTokens[pendingTokenIndex]
  pendingTokenIndex += 1
  if pendingTokenIndex == pendingTokens.count {
    pendingTokens.removeAll(keepingCapacity: true)
    pendingTokenIndex = 0
  }
  return token
}
```

- [ ] **Step 5: Run YAML tokenizer tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidYAML
```

Expected: pass.

---

### Task 7: Reduce YAML Block Scalar Array Copies

**Files:**
- Modify: `Sources/Solid/YAML/YAMLTokenizer.swift`
- Test: `Tests/SolidYAMLTests/YAMLTokenizerTests.swift`

- [ ] **Step 1: Add block scalar chomp regression test**

Add or verify:

```swift
@Test("Block scalar chomp behavior remains stable")
func blockScalarChompBehavior() throws {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data("a: |-\n  one\n  two\nb: >+\n  three\n  four\n\n".utf8), isFinal: true)

  var scalarTexts: [String] = []
  while let token = try tokenizer.readToken() {
    if case .scalar(let scalar) = token {
      scalarTexts.append(try scalar.region.string())
    }
  }

  #expect(scalarTexts.contains("one\ntwo"))
  #expect(scalarTexts.contains("three four\n\n"))
}
```

- [ ] **Step 2: Remove Array(lines) in literal join**

Replace:

```swift
var activeLines = Array(lines)
```

with an end index:

```swift
var endIndex = lines.count
if chomp != .keep {
  while endIndex > 0, lines[endIndex - 1].line.isEmpty {
    endIndex -= 1
  }
}
```

Build output with indexed iteration:

```swift
var text = ""
for idx in 0..<endIndex {
  if idx > 0 { text.append("\n") }
  text.append(lines[idx].line)
}
```

- [ ] **Step 3: Remove Array(lines) in folded join**

Apply the same end-index pattern in `joinFoldedLines`.

Replace:

```swift
for entry in activeLines {
```

with:

```swift
for idx in 0..<endIndex {
  let entry = lines[idx]
```

Update `.keep` empty handling from `activeLines.isEmpty` to `endIndex == 0`.

- [ ] **Step 4: Run YAML tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidYAML
```

Expected: pass.

---

### Task 8: Add Single-Consumer Protection to Async Drivers

**Files:**
- Modify: `Sources/Solid/Data/Format/FormatStreamReaderDriver.swift`
- Modify: `Sources/Solid/Data/Format/FormatStreamWriterDriver.swift`
- Test: `Tests/SolidDataTests/FormatStreamDriverTests.swift`

- [ ] **Step 1: Decide the model**

Use single-consumer enforcement, not actors, for this task. These drivers wrap noncopyable parsers/encoders and are intended as stateful stream cursors. Actor conversion would be a public shape and isolation change; a lightweight guard preserves API and makes misuse explicit.

- [ ] **Step 2: Add state flags**

In `FormatStreamReaderDriver` add:

```swift
private var nextInProgress = false
```

In `FormatStreamWriterDriver` add:

```swift
private var operationInProgress = false
```

- [ ] **Step 3: Add an error**

If there is no existing stream misuse error, add a private error in each file:

```swift
private enum DriverConcurrencyError: Swift.Error {
  case concurrentOperation
}
```

If the project has a public `IOError` case that fits, use that instead and do not add a new public API.

- [ ] **Step 4: Guard reader next()**

At the top of `next()`:

```swift
guard !nextInProgress else {
  throw DriverConcurrencyError.concurrentOperation
}
nextInProgress = true
defer { nextInProgress = false }
```

This is not a cross-thread lock. It prevents overlapping calls on the same executor/task path and documents the single-consumer contract. If strict cross-thread protection is required by tests or compiler diagnostics, replace the flag with `Mutex<Bool>`.

- [ ] **Step 5: Guard writer write and finish**

At the top of `write(_:)` and `finish()`:

```swift
guard !operationInProgress else {
  throw DriverConcurrencyError.concurrentOperation
}
operationInProgress = true
defer { operationInProgress = false }
```

- [ ] **Step 6: Add documentation comments**

Add to both driver type comments:

```swift
/// This driver is a single-consumer cursor. Do not call `next()` concurrently
/// on the same instance.
```

and:

```swift
/// This driver is a single-writer cursor. Do not call `write(_:)` or `finish()`
/// concurrently on the same instance.
```

- [ ] **Step 7: Run SolidData**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidData
```

Expected: pass.

---

### Task 9: Evaluate ContainerStack Inline Storage

**Files:**
- Modify: `Sources/Solid/Data/Format/ContainerStack.swift`
- Test: `Tests/SolidDataTests/ParseEventDecoderTests.swift`
- Test: `Tests/SolidJSONTests/JSONStreamReaderTests.swift`
- Test: `Tests/SolidCBORTests/CBORStreamTests.swift`
- Test: `Tests/SolidYAMLTests/YAMLTokenizerTests.swift`

- [ ] **Step 1: Add deep nesting regression test**

In an existing data decoder test file, add:

```swift
@Test("ContainerStack handles deep nesting")
func containerStackDeepNesting() throws {
  var stack = ContainerStack()
  for _ in 0..<128 {
    stack.pushArray(count: nil)
  }
  #expect(stack.count == 128)
  for _ in 0..<128 {
    _ = try stack.pop()
  }
  #expect(stack.isEmpty)
}
```

- [ ] **Step 2: Add capacity reservation without InlineArray first**

Before attempting a more invasive `InlineArray` implementation, add a small initializer:

```swift
public init(reservingCapacity capacity: Int) {
  frames.reserveCapacity(capacity)
}
```

Keep the existing `public init()`.

- [ ] **Step 3: Use reserved stack where counts are known**

Do not force all readers to predict depth. Only use the reserved initializer in tests or local builders if there is a known depth. If no call site has a known depth, leave this as API groundwork and stop here.

- [ ] **Step 4: Defer InlineArray unless profiling proves it**

Do not implement custom inline storage in this pass unless benchmark data shows `ContainerStack.frames.append` as a top allocation source. The risk is not justified before `ParseBuffer` and `ScalarRef` are fixed.

- [ ] **Step 5: Run targeted tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter ParseEventDecoderTests
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidJSON
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidCBOR
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidYAML
```

Expected: pass.

---

### Task 10: Benchmark Smoke Pass

**Files:**
- No required source changes.
- Optional: `Benchmarks/SolidJSONBenchmark/SolidJSONBenchmark.swift`
- Optional: `Benchmarks/SolidCBORBenchmark/SolidCBORBenchmark.swift`
- Optional: `Benchmarks/SolidYAMLBenchmark/SolidYAMLBenchmark.swift`

- [ ] **Step 1: Run full tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox
```

Expected: full suite passes.

- [ ] **Step 2: Run available benchmark smoke targets**

Inspect package targets:

```bash
swift package describe
```

Run the benchmark executables that exist in this checkout. Use the project’s existing benchmark invocation if documented. If they are plain executable targets, run:

```bash
swift run -c release SolidJSONBenchmark
swift run -c release SolidCBORBenchmark
swift run -c release SolidYAMLBenchmark
```

Expected: benchmark targets build and run. If target names differ, use the names from `swift package describe`.

- [ ] **Step 3: Compare allocation-sensitive behavior**

Record qualitative results in the execution thread:

```text
Performance smoke notes:
- ParseBuffer region tests pass.
- ScalarRef cached materialization still runs resolver once.
- JSON/CBOR/YAML suites pass.
- Benchmark smoke targets build/run.
```

---

## Deferred Work

These are intentionally not in the main implementation sequence:

- Full byte/span YAML tokenizer rewrite. This is a larger parser design effort and should be its own plan.
- Actor-based stream drivers. Use only if the project wants concurrent multi-consumer semantics for one driver instance.
- Adding a new atomic package dependency for fully allocation-free lazy scalar caches.
- Generic tree assembler rewrite for `ParseEventDecoder` and YAML node builders. It may reduce code duplication, but it is not required for the current performance findings.

## Self-Review

- Spec coverage:
  - Finding 1 is covered by Task 3.
  - Finding 2 is covered by Tasks 2 and 4.
  - Finding 3 is partially addressed by Task 7 and explicitly deferred for full byte/span rewrite.
  - Finding 4 is covered by Task 6.
  - Finding 5 is covered by Task 8.
  - JSON fast path is covered by Task 5.
  - CBOR deterministic buffering was recently improved; this plan does not reopen it unless benchmarks identify it as hot after shared fixes.

- Placeholder scan:
  - No task uses TBD/TODO language.
  - Deferred work is explicitly out of scope.

- Type consistency:
  - `ParseBuffer.Region`, `ScalarRef`, `RegionScalarResolver`, `CBOREventReader`, `JSONScalarResolver`, `YAMLTokenizer`, and driver names match current code.

# Parser Performance and Correctness Gaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining correctness and performance gaps found after the push parser / zero-copy refactor.

**Architecture:** Treat JSON strict single-document validation as the only P1 correctness fix. Keep YAML flow parsing on the lexer/structure split, but improve its streaming behavior by flushing mapping values after `:` when the value position is no longer ambiguous. Keep `ParseBuffer.Region` zero-copy by default, but add explicit retention diagnostics/detachment tools so consumers can manage long-lived scalar references.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftPM, `ParseBuffer.Region`, `JSONEventReader`, `FormatValueReader`, `YAMLFlowLexer`, `YAMLFlowStructureAdapter`, `ContainerStack`.

---

## File Map

- Modify `Sources/Solid/JSON/JSONEventReader.swift`
  - Reject non-whitespace bytes after the single JSON root value when the reader is drained.
  - Keep whitespace after the root valid.
- Modify `Sources/Solid/JSON/JSONValueReader.swift`
  - Configure synchronous JSON reads/validation to require stream exhaustion after the first decoded value.
- Modify `Sources/Solid/Data/Format/FormatValueReader.swift`
  - Add optional strict end-of-stream validation for formats with exactly one root value.
- Modify `Tests/SolidJSONTests/JSONStreamReaderTests.swift`
  - Add strict trailing-data tests for `read()`, `validateValue()`, and streamed draining.
- Modify `Sources/Solid/YAML/YAMLTokenizer.swift`
  - Track per-line/per-column locations in `YAMLFlowLexer`.
  - Allow `YAMLFlowStructureAdapter` to stream mapping value tokens after `:`.
- Modify `Tests/SolidYAMLTests/YAMLTokenizerTests.swift`
  - Add flow error-location tests.
  - Add streaming tests that prove large mapping values begin emitting before the mapping entry closes.
- Modify `Sources/Solid/Data/Format/ParseBuffer.swift`
  - Add region retention introspection and explicit detachment APIs.
  - Document retained segment behavior.
- Modify `Tests/SolidDataTests/ScalarRefTests.swift`
  - Add retained-size and detached-region tests.
- Modify `Sources/Solid/JSON/JSONEventReader.swift`
  - Remove the duplicate `ContainerStack` from JSON after strict behavior is green.
- Modify `Tests/SolidJSONTests/JSONStreamReaderTests.swift`
  - Add nested object/array parity tests covering key/value transitions after the stack cleanup.

---

### Task 1: Make JSON Synchronous Reads Strict About Trailing Root Data

**Files:**
- Modify: `Sources/Solid/Data/Format/FormatValueReader.swift`
- Modify: `Sources/Solid/JSON/JSONValueReader.swift`
- Modify: `Sources/Solid/JSON/JSONEventReader.swift`
- Test: `Tests/SolidJSONTests/JSONStreamReaderTests.swift`

- [ ] **Step 1: Add failing tests for trailing JSON data**

Add these tests to `JSONStreamReaderTests`:

```swift
@Test("JSON value reader rejects trailing root value")
func valueReaderRejectsTrailingRootValue() throws {
  var reader = JSONValueReader(string: "1 2")

  #expect(throws: JSON.Error.self) {
    _ = try reader.read()
  }
}

@Test("JSON value reader rejects trailing garbage")
func valueReaderRejectsTrailingGarbage() throws {
  var reader = JSONValueReader(string: #"{"a":1} garbage"#)

  #expect(throws: JSON.Error.self) {
    _ = try reader.read()
  }
}

@Test("JSON value reader allows trailing whitespace")
func valueReaderAllowsTrailingWhitespace() throws {
  var reader = JSONValueReader(string: #"{"a":1}   \#n\t  "#)

  #expect(try reader.read() == .object([.string("a"): .number(1)]))
}

@Test("JSON validation rejects trailing root data")
func validationRejectsTrailingRootData() throws {
  var reader = JSONValueReader(string: "true false")

  #expect(throws: JSON.Error.self) {
    try reader.validateValue()
  }
}

@Test("JSON stream driver reports trailing data when drained")
func streamDriverReportsTrailingDataWhenDrained() async throws {
  let source = ChunkedSource(data: Data("1 2".utf8), chunkSizes: [1])
  let reader = JSONStreamReader()
  let driver = FormatStreamReaderDriver(reader: reader, source: source, bufferSize: 1)

  #expect(try await driver.next() == .scalar(.materialized(.number(1))))
  await #expect(throws: JSON.Error.self) {
    _ = try await driver.next()
  }
}
```

If `#n` is not accepted in the raw string interpolation context, replace that line with:

```swift
var reader = JSONValueReader(string: "{\"a\":1}   \n\t  ")
```

- [ ] **Step 2: Run the JSON trailing tests and verify they fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter JSONStreamReaderTests/valueReaderRejectsTrailingRootValue
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter JSONStreamReaderTests/validationRejectsTrailingRootData
```

Expected before implementation: at least the value/validation tests fail because trailing content is ignored.

- [ ] **Step 3: Add strict end-of-stream support to `FormatValueReader`**

Update `FormatValueReader` with two new stored properties:

```swift
private let requiresEndOfStream: Bool
private let trailingDataError: @Sendable () -> any Swift.Error
```

Extend the initializer:

```swift
public init(
  reader: consuming Reader,
  data: Data,
  format: Format,
  scalarResolver: (any ScalarResolver)? = nil,
  unexpectedEndError: @escaping @Sendable () -> any Swift.Error,
  requiresEndOfStream: Bool = false,
  trailingDataError: @escaping @Sendable () -> any Swift.Error = {
    FormatStreamDriverError.operationInProgress
  }
)
```

Set the new properties in the initializer. The default `trailingDataError` is never used unless `requiresEndOfStream` is true; format-specific readers should supply a real error.

Modify `read()` so that when `decoder.isComplete`:

```swift
let value = try decoder.finish()
if firstValue == nil {
  firstValue = value
  if !requiresEndOfStream {
    done = true
    break
  }
  decoder = makeDecoder()
  continue
}
throw trailingDataError()
```

When `requiresEndOfStream` is true, keep calling `reader.read(input: Data(), isFinal: true, output: &out)` until `.endOfStream`. If any additional event is produced after `firstValue` is set, throw `trailingDataError()`.

- [ ] **Step 4: Configure JSON value reads for strict exhaustion**

In `JSONValueReader.init(data:)`, pass:

```swift
requiresEndOfStream: true,
trailingDataError: {
  JSON.Error.invalidStructure("Extra data after root value")
}
```

- [ ] **Step 5: Make `JSONEventReader` reject non-whitespace after root when drained**

Replace the `rootState == .complete` branch in `JSONEventReader.readEvent()` with logic that:

1. Calls `skipWhitespace()`.
2. If the buffer is empty and `finalReceived` is false, returns `nil`.
3. If the buffer is empty and `finalReceived` is true, sets `_isFinished = true` and returns `nil`.
4. If any byte remains, throws `JSON.Error.invalidStructure("Extra data after root value")`.

The shape should be:

```swift
if case .complete = rootState {
  skipWhitespace()
  guard !buffer.isEmpty else {
    if finalReceived {
      _isFinished = true
    }
    return nil
  }
  throw JSON.Error.invalidStructure("Extra data after root value")
}
```

- [ ] **Step 6: Run JSON verification**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidJSON
```

Expected: all JSON tests pass, including the new trailing-data tests.

---

### Task 2: Stream YAML Flow Mapping Values After `:`

**Files:**
- Modify: `Sources/Solid/YAML/YAMLTokenizer.swift`
- Test: `Tests/SolidYAMLTests/YAMLTokenizerTests.swift`

- [ ] **Step 1: Add a failing streaming test for root flow mapping values**

Add this test to `YAMLTokenizerTests` near the existing flow streaming tests:

```swift
@Test("flow mapping streams value collection after colon before entry closes")
func flowMappingStreamsValueCollectionAfterColon() throws {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data("{key: [a, ".utf8), isFinal: false)

  try expectDocumentStart(try tokenizer.readToken(), explicit: false)
  try expectBeginMapping(try tokenizer.readToken(), style: .flow)
  try expectRetainedScalar(try tokenizer.readToken(), text: "key")
  try expectBeginSequence(try tokenizer.readToken(), style: .flow)
  try expectRetainedScalar(try tokenizer.readToken(), text: "a")
  #expect(try tokenizer.readToken() == nil)

  tokenizer.feedInput(Data("b]}\n".utf8), isFinal: true)

  try expectRetainedScalar(try tokenizer.readToken(), text: "b")
  try expectEndSequence(try tokenizer.readToken())
  try expectEndMapping(try tokenizer.readToken())
  try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
  #expect(try tokenizer.readToken() == nil)
}
```

This test protects the desired behavior: after the `:` in `{key: ...}`, the key is no longer ambiguous and the value sequence can be streamed before the closing `}`.

- [ ] **Step 2: Run the new YAML test and verify it fails**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests/flowMappingStreamsValueCollectionAfterColon
```

Expected before implementation: the key/value collection is delayed until the mapping closes.

- [ ] **Step 3: Add streaming state to `YAMLFlowStructureAdapter.Frame`**

In `YAMLFlowStructureAdapter.Frame`, add:

```swift
var mappingValueStreamsDirectly = false
```

This flag means the mapping has already emitted its key and the current value position is structurally decided.

- [ ] **Step 4: Flush mapping keys when `:` is consumed**

In `consumeColon(location:)`, for the `.mapping` case when `mappingMode == .key`:

1. Normalize an empty key to `emptyScalar()`.
2. Append the normalized key tokens to the frame sink immediately.
3. Clear `mappingKey`.
4. Set `mappingMode = .value`.
5. Set `mappingValueStreamsDirectly = true`.

The important behavior is that the parent/root queue sees the key before the value starts.

- [ ] **Step 5: Append mapping value tokens directly when safe**

In `appendNodeTokens(_:)`, update the `.mapping` / `.value` branch:

```swift
case .value:
  if frames[frames.count - 1].mappingValueStreamsDirectly {
    var frame = frames.removeLast()
    appendToFrameSink(tokens, frame: &frame)
    frames.append(frame)
  } else {
    frames[frames.count - 1].mappingValue.append(contentsOf: tokens)
  }
```

Do not direct-stream mapping keys; keys remain ambiguous until `:` or entry close.

- [ ] **Step 6: Avoid emitting direct-streamed mapping values twice**

In `finishMappingEntry(in:)`, when `mappingMode == .value` and `mappingValueStreamsDirectly == true`, append only missing empty value tokens:

```swift
case .value:
  if frame.mappingValueStreamsDirectly {
    if frame.mappingValue.isEmpty {
      appendToFrameSink([emptyScalar()], frame: &frame)
    } else {
      appendToFrameSink(frame.mappingValue, frame: &frame)
    }
  } else {
    appendToFrameSink(normalizedNodeTokens(frame.mappingKey), frame: &frame)
    appendToFrameSink(normalizedNodeTokens(frame.mappingValue), frame: &frame)
  }
```

Then reset:

```swift
frame.mappingValueStreamsDirectly = false
```

If Step 5 no longer stores any direct-streamed value tokens in `mappingValue`, the `mappingValue.isEmpty` branch should emit an empty scalar only when no value token was ever seen. Add a boolean `mappingValueSawToken` if needed to distinguish `{a:}` from `{a: []}`.

- [ ] **Step 7: Run YAML tokenizer verification**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
```

Expected: all tokenizer tests pass.

---

### Task 3: Track Accurate Locations in YAML Flow Lexing

**Files:**
- Modify: `Sources/Solid/YAML/YAMLTokenizer.swift`
- Test: `Tests/SolidYAMLTests/YAMLTokenizerTests.swift`

- [ ] **Step 1: Add failing error-location tests**

Add tests for multi-line flow errors:

```swift
@Test("multiline flow invalid close reports offending line")
func multilineFlowInvalidCloseReportsOffendingLine() throws {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data("[\n  a\n}\n".utf8), isFinal: true)

  try expectDocumentStart(try tokenizer.readToken(), explicit: false)
  try expectBeginSequence(try tokenizer.readToken(), style: .flow)

  do {
    while try tokenizer.readToken() != nil {}
    Issue.record("Expected invalid flow close")
  } catch let error as YAML.ParseError {
    guard case .invalidSyntax(_, let location) = error else {
      Issue.record("Expected invalidSyntax, got \(error)")
      return
    }
    #expect(location.line == 3)
    #expect(location.column == 1)
  }
}

@Test("multiline flow missing comma reports current line")
func multilineFlowMissingCommaReportsCurrentLine() throws {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data("[\n  a\n  b\n]\n".utf8), isFinal: true)

  try expectDocumentStart(try tokenizer.readToken(), explicit: false)
  try expectBeginSequence(try tokenizer.readToken(), style: .flow)

  do {
    while try tokenizer.readToken() != nil {}
    Issue.record("Expected missing comma error")
  } catch let error as YAML.ParseError {
    guard case .invalidSyntax(_, let location) = error else {
      Issue.record("Expected invalidSyntax, got \(error)")
      return
    }
    #expect(location.line == 3)
  }
}
```

- [ ] **Step 2: Run the new location tests and verify they fail**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests/multilineFlowInvalidCloseReportsOffendingLine
```

Expected before implementation: error location points at the flow opener or an imprecise line.

- [ ] **Step 3: Add line/column inputs to `PendingFlow.feedLine` and `YAMLFlowLexer.feedLine`**

Change `PendingFlow.feedLine` to accept:

```swift
line: Int,
column: Int,
```

Change `YAMLFlowLexer.feedLine` to accept:

```swift
mutating func feedLine(
  _ region: ParseBuffer.Region,
  leadingNewline: Bool,
  line: Int,
  column: Int
)
```

Use the current tokenizer `lineNumber` and the column corresponding to `contentStart`. For current code, `column` should be `indent + 1` for normal content lines.

- [ ] **Step 4: Emit token locations from byte offsets**

Inside `YAMLFlowLexer.feedLine`, compute token location from the current byte index:

```swift
private func location(line: Int, column: Int, offset: Int) -> YAML.ParseError.Location {
  YAML.ParseError.Location(line: line, column: column + offset)
}
```

Use this location for punctuation, scalar, tag, anchor, alias, invalid, line-break, and EOF tokens emitted from that line. Keep the opener location only for EOF errors where no current line exists.

- [ ] **Step 5: Pass precise locations into the structural adapter**

The adapter already stores locations on `YAMLFlowLexToken`; after Step 4, do not substitute the opener-level `location` for token-level errors. Existing `consumeComma`, `consumeColon`, `end`, and invalid-token paths should use `token.location` / the location already carried by the token.

- [ ] **Step 6: Run YAML verification**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidYAML
```

Expected: tokenizer and YAML suites pass with improved error locations.

---

### Task 4: Add Explicit ParseBuffer Region Retention Tools

**Files:**
- Modify: `Sources/Solid/Data/Format/ParseBuffer.swift`
- Test: `Tests/SolidDataTests/ScalarRefTests.swift`

- [ ] **Step 1: Add tests for retained storage size and detachment**

Add tests:

```swift
@Test("ParseBuffer region reports retained storage size")
func parseBufferRegionReportsRetainedStorageSize() throws {
  var buffer = ParseBuffer()
  buffer.append(Data(repeating: 0x61, count: 1024))

  let start = buffer.mark()
  try buffer.advance(count: 1)
  let region = buffer.region(from: start, to: buffer.mark())

  #expect(region.count == 1)
  #expect(region.retainedByteCount == 1024)
}

@Test("ParseBuffer detached region copies only visible bytes")
func parseBufferDetachedRegionCopiesOnlyVisibleBytes() throws {
  var buffer = ParseBuffer()
  buffer.append(Data(repeating: 0x61, count: 1024))

  let start = buffer.mark()
  try buffer.advance(count: 1)
  let region = buffer.region(from: start, to: buffer.mark())
  let detached = region.detached()

  #expect(detached.bytes == Data([0x61]))
  #expect(detached.count == 1)
  #expect(detached.retainedByteCount == 1)
  #expect(detached.isCopied)
}
```

- [ ] **Step 2: Add `retainedByteCount` to `ParseBuffer.Region`**

Implement:

```swift
public var retainedByteCount: Int {
  switch storage {
  case .retained(let segment, _, _):
    return segment.count
  case .copied(let data):
    return data.count
  }
}
```

- [ ] **Step 3: Add explicit detachment**

Implement:

```swift
public func detached() -> Region {
  Region(copied: bytes)
}
```

This intentionally materializes only when a caller chooses to break retention. Do not add automatic copying to `ScalarRef` or parser hot paths.

- [ ] **Step 4: Update retention documentation**

Update the `ParseBuffer.Region` doc comment to say:

```swift
/// Same-segment regions retain the full source `Data` segment. This preserves
/// zero-copy scalar events, but long-lived small regions can keep large input
/// chunks alive. Use `detached()` when a caller needs to retain a small region
/// independently of the parser input segment.
```

- [ ] **Step 5: Run SolidData verification**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidData
```

Expected: all SolidData tests pass.

---

### Task 5: Remove JSON's Parallel Semantic Container Stack

**Files:**
- Modify: `Sources/Solid/JSON/JSONEventReader.swift`
- Test: `Tests/SolidJSONTests/JSONStreamReaderTests.swift`

- [ ] **Step 1: Add JSON parity tests around nested key/value transitions**

Add:

```swift
@Test("JSON nested object and array key value transitions remain valid")
func nestedObjectArrayKeyValueTransitionsRemainValid() async throws {
  let json = #"{"outer":{"array":[{"k":"v"},2],"empty":{}},"tail":true}"#
  let streamed = try await parseStreamed(json: json, chunkSizes: [1])
  var reader = JSONValueReader(string: json)
  #expect(streamed == (try reader.read()))
}

@Test("JSON rejects object value without colon after stack cleanup")
func objectValueWithoutColonRejected() throws {
  var reader = JSONValueReader(string: #"{"a" 1}"#)

  #expect(throws: JSON.Error.self) {
    _ = try reader.read()
  }
}

@Test("JSON rejects missing object value after stack cleanup")
func objectMissingValueRejected() throws {
  var reader = JSONValueReader(string: #"{"a":}"#)

  #expect(throws: JSON.Error.self) {
    _ = try reader.read()
  }
}
```

- [ ] **Step 2: Run the new JSON tests before refactor**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter JSONStreamReaderTests/nestedObjectArrayKeyValueTransitionsRemainValid
```

Expected: tests pass before refactor, proving behavior baseline.

- [ ] **Step 3: Remove `semanticContainers` from `JSONEventReader`**

Delete:

```swift
private var semanticContainers = ContainerStack()
```

Remove all calls to:

```swift
semanticContainers.pushArray(...)
semanticContainers.pushObject(...)
semanticContainers.pop()
semanticContainers.didFinishContainerValue()
semanticContainers.didFinishScalarValue()
```

- [ ] **Step 4: Use JSON delimiter frames as the single source of truth**

Keep the existing `containers: ContiguousArray<ContainerFrame>` as the only stack. Ensure:

- `validateValuePosition()` accepts values only in root, array value positions, or object `.expectValue`.
- `didFinishValue()` transitions:
  - array `.expectValue` / `.expectValueOrEnd` -> `.expectCommaOrEnd`
  - object `.expectValue` -> `.expectCommaOrEnd`
  - root `.expectingValue` -> `.complete`
- string scalar in object key position transitions object `.expectKey` / `.expectKeyOrEnd` -> `.expectColon`.
- non-string scalar in object key position still throws.

Do not change JSON delimiter validation semantics.

- [ ] **Step 5: Run JSON verification**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidJSON
```

Expected: all JSON tests pass.

---

### Task 6: Full Verification and Grep Checks

**Files:**
- No code changes unless verification exposes issues.

- [ ] **Step 1: Run targeted suites**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidData
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidJSON
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidYAML
```

Expected: all targeted suites pass.

- [ ] **Step 2: Run the full suite**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox
```

Expected: full suite passes.

- [ ] **Step 3: Check for old flow parser regressions**

Run:

```bash
rg -n "YAMLFlowScanner|YAMLFlowTokenBuffer|YAMLFlowByteView|YAMLFlowByteSource|flowBytesAreComplete|materializedFlowBytes" Sources/Solid/YAML
```

Expected: no hits.

- [ ] **Step 4: Check JSON duplicate stack cleanup**

Run:

```bash
rg -n "semanticContainers|ContainerStack" Sources/Solid/JSON/JSONEventReader.swift
```

Expected: no hits after Task 5.

---

## Rollout Notes

- Task 1 should be implemented first because it fixes a correctness issue.
- Tasks 2 and 3 are independent YAML flow improvements and can be implemented separately.
- Task 4 intentionally does not add automatic region copying. Zero-copy remains the default; long-lived consumers get explicit tools to detach.
- Task 5 is a low-risk cleanup only after JSON strict behavior is green.

## Self-Review

- All five review findings are covered:
  - JSON trailing data: Task 1.
  - YAML flow mapping value buffering: Task 2.
  - YAML flow error locations: Task 3.
  - ParseBuffer retained segment memory behavior: Task 4.
  - JSON duplicate container stacks: Task 5.
- No public event API changes are required.
- The plan keeps YAML correctness and existing yaml-test-suite parity as the guardrail.

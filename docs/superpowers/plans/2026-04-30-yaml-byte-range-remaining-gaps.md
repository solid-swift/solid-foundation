# YAML Byte/Range Remaining Gaps Implementation Plan

> Status note: The Option 1 stopgap has been implemented. `YAMLFlowScanner`
> now emits into `PendingTokenQueue` and uses a narrow replay buffer for
> ambiguous flow sequence candidates. The future lexer/structure split remains
> tracked in root `TODO.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the remaining YAML byte/range scanner gaps that still affect performance or streaming behavior.

**Architecture:** Keep public APIs unchanged and keep the existing tokenizer-backed YAML pipeline. Replace the remaining batch flow grammar path with incremental token emission, remove dead string-first helper overloads from production code, and add narrow tests around retained regions and streaming boundaries.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftPM, `ParseBuffer.Region`, noncopyable tokenizer/scanner state, `ContiguousArray`.

---

## File Map

- Modify `Sources/Solid/YAML/YAMLTokenizer.swift`
  - Consolidate flow scanning and grammar into `YAMLFlowScanner`.
  - Emit `YAMLRawToken` directly into `PendingTokenQueue` when complete flow nodes are recognized.
  - Keep retained input regions for same-line flow scalars.
  - Materialize generated `Data` only for normalized quoted scalars and multiline folded flow scalars.
  - Remove unused string-first helper overloads.
- Modify `Tests/SolidYAMLTests/YAMLTokenizerTests.swift`
  - Add streaming flow tests that assert no token is emitted before structurally complete flow input.
  - Add retained/generator region tests for flow scalars.
  - Keep yaml-test-suite parity coverage.

## Non-Goals

- Do not change `YAMLRawToken`, `YAMLRawScalar`, `ParseEvent`, `EmitEvent`, reader APIs, or writer APIs.
- Do not add broad `@inlinable` annotations without benchmark evidence.
- Do not replace all string conversion in quoted/block scalar normalization; those paths intentionally produce normalized string or `Data` output.

---

### Task 1: Add Tests For Direct Flow Emission Semantics

**Files:**
- Modify: `Tests/SolidYAMLTests/YAMLTokenizerTests.swift`

- [ ] **Step 1: Add a test proving incomplete flow input does not emit value tokens**

Add this test near the existing flow tokenizer tests:

```swift
@Test("flow scanner waits for balanced input before emitting tokens")
func flowScannerWaitsForBalancedInput() throws {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data("[a, ".utf8), isFinal: false)

  try expectDocumentStart(try tokenizer.readToken(), explicit: false)
  #expect(try tokenizer.readToken() == nil)

  tokenizer.feedInput(Data("{b: c}".utf8), isFinal: false)
  #expect(try tokenizer.readToken() == nil)

  tokenizer.feedInput(Data("]\n".utf8), isFinal: true)
  try expectBeginSequence(try tokenizer.readToken(), style: .flow)
  try expectRetainedScalar(try tokenizer.readToken(), text: "a")
  try expectBeginMapping(try tokenizer.readToken(), style: .flow)
  try expectScalarText(try tokenizer.readToken(), "b")
  try expectScalarText(try tokenizer.readToken(), "c")
  try expectEndMapping(try tokenizer.readToken())
  try expectEndSequence(try tokenizer.readToken())
  try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
  #expect(try tokenizer.readToken() == nil)
}
```

- [ ] **Step 2: Add helpers for scalar text if missing**

If `expectScalarText` is not already present in the file, add it near other test helpers:

```swift
private func expectScalarText(
  _ token: YAMLRawToken?,
  _ expected: String,
  sourceLocation: SourceLocation = #_sourceLocation
) throws {
  let scalar = try expectScalar(token, sourceLocation: sourceLocation)
  #expect(try scalar.region.string() == expected, sourceLocation: sourceLocation)
}
```

- [ ] **Step 3: Run the targeted test**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter 'YAMLTokenizerTests/flowScannerWaitsForBalancedInput'
```

Expected: PASS on current code. This is a characterization test to protect streaming behavior while refactoring internals.

- [ ] **Step 4: Add a retained-region test for same-line flow after refactor**

Add:

```swift
@Test("same-line flow plain scalars keep retained source regions after direct scanner emission")
func directFlowScannerKeepsRetainedSameLinePlainScalars() throws {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data("[alpha, {beta: gamma}]\n".utf8), isFinal: true)

  try expectDocumentStart(try tokenizer.readToken(), explicit: false)
  try expectBeginSequence(try tokenizer.readToken(), style: .flow)
  try expectRetainedScalar(try tokenizer.readToken(), text: "alpha")
  try expectBeginMapping(try tokenizer.readToken(), style: .flow)
  try expectRetainedScalar(try tokenizer.readToken(), text: "beta")
  try expectRetainedScalar(try tokenizer.readToken(), text: "gamma")
  try expectEndMapping(try tokenizer.readToken())
  try expectEndSequence(try tokenizer.readToken())
  try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
  #expect(try tokenizer.readToken() == nil)
}
```

- [ ] **Step 5: Run tokenizer tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
```

Expected: PASS.

---

### Task 2: Replace `YAMLFlowGrammar` Batch Parser With Scanner-Owned Emission

**Files:**
- Modify: `Sources/Solid/YAML/YAMLTokenizer.swift`

- [ ] **Step 1: Change `YAMLFlowScanner.parseIfComplete` to emit into a queue**

Replace:

```swift
func parseIfComplete(tagHandles: [String: String]) throws -> ContiguousArray<YAMLRawToken>?
```

with:

```swift
mutating func emitIfComplete(
  tagHandles: [String: String],
  into queue: inout YAMLTokenizer.PendingTokenQueue
) throws -> Bool
```

Implementation shape:

```swift
mutating func emitIfComplete(
  tagHandles: [String: String],
  into queue: inout YAMLTokenizer.PendingTokenQueue
) throws -> Bool {
  guard balance.isComplete else {
    return false
  }
  let tokens = try parse(tagHandles: tagHandles)
  for token in tokens {
    queue.append(token)
  }
  return true
}
```

This keeps behavior unchanged for the first refactor slice. It moves ownership of emission into the scanner call site before replacing the internals.

- [ ] **Step 2: Update scanner call sites**

In `appendFlowTokens(_ region:location:minimumContinuationIndent:)`, replace:

```swift
if let tokens = try scanner.parseIfComplete(tagHandles: tagHandles) {
  appendParsedFlowTokens(tokens)
} else {
  pendingFlow = PendingFlow(...)
}
```

with:

```swift
if try scanner.emitIfComplete(tagHandles: tagHandles, into: &pendingTokens) {
  markDocumentContent()
} else {
  pendingFlow = PendingFlow(
    scanner: scanner,
    opener: region.firstByte ?? .leftSquare,
    minimumContinuationIndent: minimumContinuationIndent
  )
}
```

Use the same pattern in `appendFlowTokens(_ data:sourceRegion:location:minimumContinuationIndent:)`.

- [ ] **Step 3: Update pending flow continuation**

In the `pendingFlow != nil` branch inside `processLine`, replace:

```swift
if let tokens = try pendingFlow?.scanner.parseIfComplete(tagHandles: tagHandles) {
  pendingFlow = nil
  appendParsedFlowTokens(tokens)
}
```

with:

```swift
if try pendingFlow?.scanner.emitIfComplete(tagHandles: tagHandles, into: &pendingTokens) == true {
  pendingFlow = nil
  markDocumentContent()
}
```

- [ ] **Step 4: Update final flow completion**

Replace `finish(tagHandles:) -> ContiguousArray<YAMLRawToken>` with:

```swift
mutating func finish(
  tagHandles: [String: String],
  into queue: inout YAMLTokenizer.PendingTokenQueue
) throws {
  guard balance.isComplete else {
    throw YAML.ParseError.incompleteInput(location: location)
  }
  let tokens = try parse(tagHandles: tagHandles)
  for token in tokens {
    queue.append(token)
  }
}
```

Update `finishPendingFlow()`:

```swift
private mutating func finishPendingFlow() throws {
  guard pendingFlow != nil else {
    return
  }
  try pendingFlow!.scanner.finish(tagHandles: tagHandles, into: &pendingTokens)
  pendingFlow = nil
  markDocumentContent()
}
```

- [ ] **Step 5: Run tokenizer tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
```

Expected: PASS. This step intentionally preserves internal batch parsing while moving emission ownership.

---

### Task 3: Make Flow Grammar Incremental Over Segments

**Files:**
- Modify: `Sources/Solid/YAML/YAMLTokenizer.swift`

- [ ] **Step 1: Introduce an internal flow byte source**

Add below `YAMLFlowSegment`:

```swift
private struct YAMLFlowByteSource: Sendable {
  private let segments: ContiguousArray<YAMLFlowSegment>

  init(_ segments: ContiguousArray<YAMLFlowSegment>) {
    self.segments = segments
  }

  var count: Int {
    segments.reduce(0) { partial, segment in partial + segment.byteCount }
  }

  func materializeRange(_ range: Range<Int>) -> Data {
    var output = Data()
    output.reserveCapacity(range.count)
    var absolute = 0
    for segment in segments {
      let segmentCount = segment.byteCount
      let segmentRange = absolute..<(absolute + segmentCount)
      let overlapLower = max(range.lowerBound, segmentRange.lowerBound)
      let overlapUpper = min(range.upperBound, segmentRange.upperBound)
      if overlapLower < overlapUpper {
        appendSegmentBytes(
          segment,
          localRange: (overlapLower - absolute)..<(overlapUpper - absolute),
          to: &output
        )
      }
      absolute += segmentCount
    }
    return output
  }

  private func appendSegmentBytes(
    _ segment: YAMLFlowSegment,
    localRange: Range<Int>,
    to output: inout Data
  ) {
    var skippedNewline = 0
    if segment.leadingNewline {
      if localRange.contains(0) {
        output.append(.newline)
      }
      skippedNewline = 1
    }
    let payloadRange = max(0, localRange.lowerBound - skippedNewline)..<max(0, localRange.upperBound - skippedNewline)
    guard !payloadRange.isEmpty else {
      return
    }
    if let region = segment.region {
      let subregion = region.subregion(payloadRange)
      subregion.withUnsafeBytes { rawBuffer in
        let bytes = rawBuffer.bindMemory(to: UInt8.self)
        guard let baseAddress = bytes.baseAddress else { return }
        output.append(baseAddress, count: bytes.count)
      }
    } else if let generatedBytes = segment.generatedBytes {
      output.append(generatedBytes[payloadRange])
    }
  }
}
```

- [ ] **Step 2: Replace `materializedFlowBytes()` use for parser setup**

Keep the single-retained-region fast path. For multi-segment flow, initialize a scanner grammar with `YAMLFlowByteSource` instead of a contiguous `Data` buffer.

Add a second grammar initializer:

```swift
init(
  source: YAMLFlowByteSource,
  location: YAML.ParseError.Location,
  tagHandles: [String: String]
)
```

The grammar should store either:

```swift
private enum Input: ~Copyable {
  case contiguous(UnsafeBufferPointer<UInt8>, sourceRegion: ParseBuffer.Region?)
  case segmented(YAMLFlowByteSource)
}
```

If a noncopyable enum is too invasive for Swift ownership, use two concrete grammar types:

```swift
private struct YAMLContiguousFlowGrammar: ~Copyable { ... }
private struct YAMLSegmentedFlowGrammar: ~Copyable { ... }
```

The segmented grammar must expose:

```swift
private mutating func byte(at position: Int) -> UInt8?
private mutating func slice(_ range: Range<Int>) -> ParseBuffer.Region
private mutating func string(in range: Range<Int>) -> String
```

For multiline or normalized scalars, `slice(_:)` returns `.init(data: source.materializeRange(range))`.

- [ ] **Step 3: Preserve same-line retained scalar fast path**

Keep this behavior in the contiguous grammar:

```swift
if !containsLineBreak(in: scalarRange), let sourceRegion {
  return sourceRegion.subregion(scalarRange)
}
return .init(data: foldFlowScalarBytes(scalarRange))
```

For segmented grammar, return a retained subregion only when the scalar range falls wholly inside one retained segment without a synthetic leading newline. Otherwise return `.init(data: foldFlowScalarBytes(scalarRange))`.

- [ ] **Step 4: Remove `materializedFlowBytes()`**

After segmented grammar passes tests, delete:

```swift
private func materializedFlowBytes() -> Data
```

Then run:

```bash
rg -n "materializedFlowBytes|let data = materializedFlowBytes|YAMLFlowGrammar\\(" Sources/Solid/YAML/YAMLTokenizer.swift
```

Expected: no `materializedFlowBytes` hits. `YAMLFlowGrammar` hits are allowed until Task 4 if the type remains named that way.

- [ ] **Step 5: Run tokenizer and YAML suites**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidYAML
```

Expected: PASS.

---

### Task 4: Remove The Separate Flow Grammar Type If It Remains A Meaningful Split

**Files:**
- Modify: `Sources/Solid/YAML/YAMLTokenizer.swift`

- [ ] **Step 1: Move grammar state under `YAMLFlowScanner`**

If `YAMLFlowGrammar` remains after Task 3, nest it as:

```swift
private struct YAMLFlowScanner: ~Copyable, Sendable {
  ...

  private struct Grammar: ~Copyable {
    ...
  }
}
```

Update parser construction:

```swift
var parser = Grammar(
  bytes: bytes,
  sourceRegion: sourceRegion,
  location: location,
  tagHandles: tagHandles
)
```

or:

```swift
var parser = Grammar(
  source: YAMLFlowByteSource(segments),
  location: location,
  tagHandles: tagHandles
)
```

- [ ] **Step 2: Verify no separate flow parser/grammar symbol remains**

Run:

```bash
rg -n "YAMLFlowParser|YAMLFlowGrammar" Sources/Solid/YAML/YAMLTokenizer.swift
```

Expected: no hits.

- [ ] **Step 3: Run tokenizer tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
```

Expected: PASS.

---

### Task 5: Remove Dead String-First Helper Overloads

**Files:**
- Modify: `Sources/Solid/YAML/YAMLTokenizer.swift`

- [ ] **Step 1: Delete unused string directive helper**

Remove:

```swift
private func parseDirective(_ text: String) -> (name: String, value: String?)
```

The production path uses:

```swift
private func parseDirective(_ region: ParseBuffer.Region) throws -> YAMLDirectiveParts
```

- [ ] **Step 2: Delete unused string decorator helper if no references remain**

Run:

```bash
rg -n "parseDecorators\\(in text|parseDecorators\\(in: [^,]+ as String|parseDecorators\\(in: .*String" Sources/Solid/YAML/YAMLTokenizer.swift
```

If there are no call sites, remove:

```swift
private func parseDecorators(
  in text: String,
  location: YAML.ParseError.Location
) throws -> (tokens: ContiguousArray<YAMLRawToken>, remainder: String, isAlias: Bool)
```

and the string-only helpers it uniquely uses:

```swift
private func parseDecoratorToken(_ text: String) throws -> (String, String.SubSequence)
private func resolveTagToken(_ token: String, location: YAML.ParseError.Location) throws -> String
```

Keep `resolveTagToken` if region paths or flow grammar still use it.

- [ ] **Step 3: Delete unused string block scalar header helper**

Run:

```bash
rg -n "parseBlockScalarHeader\\(.*String|parseBlockScalarHeader\\(_ text" Sources/Solid/YAML/YAMLTokenizer.swift
```

If there are no call sites, remove:

```swift
private func parseBlockScalarHeader(
  _ text: String,
  location: YAML.ParseError.Location
) throws -> (style: YAMLScalarStyle, indent: Int?)?
```

Keep the region overload:

```swift
private func parseBlockScalarHeader(
  _ region: ParseBuffer.Region,
  location: YAML.ParseError.Location
) throws -> (style: YAMLScalarStyle, indent: Int?)?
```

- [ ] **Step 4: Run cleanup grep**

Run:

```bash
rg -n "parseDirective\\(_ text|parseDecorators\\(\\s*in text|parseBlockScalarHeader\\(\\s*_ text|stripSeparatedLineComment|decodeRegionString|YAMLFlowTokenizer|YAMLFlowParser" Sources/Solid/YAML/YAMLTokenizer.swift
```

Expected: no hits.

- [ ] **Step 5: Run tokenizer tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
```

Expected: PASS.

---

### Task 6: Optional Tiny-Stack Optimization For Flow Balance

**Files:**
- Modify: `Sources/Solid/YAML/YAMLTokenizer.swift`

- [ ] **Step 1: Measure current flow balance overhead before changing storage**

Run a benchmark smoke test:

```bash
swift run -c release SolidYAMLBenchmark
```

Expected: benchmark completes. Record the current flow-heavy YAML reader timing.

- [ ] **Step 2: Replace `YAMLFlowBalance.stack` only if benchmark justifies it**

If flow balance shows visible allocation pressure, replace:

```swift
private var stack: ContiguousArray<UInt8> = []
```

with a small-stack helper:

```swift
private struct YAMLFlowDelimiterStack: Sendable {
  private var inline = InlineArray<8, UInt8>(repeating: 0)
  private var inlineCount = 0
  private var overflow: ContiguousArray<UInt8> = []

  var last: UInt8? {
    if let overflowLast = overflow.last {
      return overflowLast
    }
    guard inlineCount > 0 else {
      return nil
    }
    return inline[inlineCount - 1]
  }

  var isEmpty: Bool {
    inlineCount == 0 && overflow.isEmpty
  }

  mutating func append(_ byte: UInt8) {
    if inlineCount < 8, overflow.isEmpty {
      inline[inlineCount] = byte
      inlineCount += 1
    } else {
      overflow.append(byte)
    }
  }

  mutating func removeLast() {
    if !overflow.isEmpty {
      overflow.removeLast()
    } else if inlineCount > 0 {
      inlineCount -= 1
    }
  }
}
```

Then change `YAMLFlowBalance` to:

```swift
private var stack = YAMLFlowDelimiterStack()
```

- [ ] **Step 3: Re-run benchmark and tests**

Run:

```bash
swift run -c release SolidYAMLBenchmark
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
```

Expected: benchmark does not regress and tests pass. If benchmark noise hides benefit, revert this task and leave `ContiguousArray`.

---

### Task 7: Final Verification

**Files:**
- No code changes.

- [ ] **Step 1: Run targeted tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
```

Expected: PASS.

- [ ] **Step 2: Run YAML tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidYAML
```

Expected: PASS.

- [ ] **Step 3: Run full package tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox
```

Expected: PASS.

- [ ] **Step 4: Run final grep acceptance**

Run:

```bash
rg -n "YAMLFlowParser|YAMLFlowGrammar|materializedFlowBytes|flowBytesAreComplete|flowBytesAreBalanced|parseDirective\\(_ text|parseDecorators\\(\\s*in text|parseBlockScalarHeader\\(\\s*_ text|stripSeparatedLineComment|decodeRegionString|YAMLFlowTokenizer" Sources/Solid/YAML/YAMLTokenizer.swift
```

Expected: no hits.

---

## Completion Criteria

- Multiline flow input is tracked as retained regions and parsed without materializing the whole flow collection as one `Data` buffer.
- Same-line plain flow scalars keep retained source region metadata.
- Multiline or normalized flow scalars use generated regions only for scalar payloads whose bytes change or cross segment/line boundaries.
- No production string-first line helper overloads remain in `YAMLTokenizer.swift`.
- `YAMLTokenizerTests`, `SolidYAML`, and the full SwiftPM test suite pass.

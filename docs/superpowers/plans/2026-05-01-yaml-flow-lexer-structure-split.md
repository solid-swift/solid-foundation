# YAML Flow Lexer / Structure Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status, 2026-05-01:** Implemented in `YAMLTokenizer.swift`. Flow parsing now uses `YAMLFlowLexer` plus `YAMLFlowStructureAdapter`; the old `YAMLFlowScanner` / recursive grammar / replay-buffer production path has been deleted. The implementation kept these helper types in `YAMLTokenizer.swift` to reuse private byte/range helpers without broadening internal API surface.

**Goal:** Replace SolidYAML's stopgap flow replay-buffer parser with a lower-level flow lexer plus structural adapter so flow streams can emit safe tokens earlier, retain scalar regions more consistently, and remove recursive flow grammar buffering.

**Architecture:** Keep `YAMLTokenizer` as the production entrypoint and keep public APIs unchanged. Split flow handling into `YAMLFlowLexer`, which emits low-level lexical tokens from retained byte regions, and `YAMLFlowStructureAdapter`, which owns lookahead, key/value ambiguity, nesting, and `YAMLRawToken` emission. Delete the stopgap `YAMLFlowScanner.Grammar` / `YAMLFlowTokenBuffer` path after parity passes.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftPM, `ParseBuffer.Region`, noncopyable scanner state, `ContiguousArray`, existing `YAMLRawToken` / `YAMLRawScalar` event model.

---

## Current Gaps This Plan Closes

- Flow parsing still waits for a structurally balanced collection before producing any flow tokens. This affects streaming behavior for large flow collections and can retain many input segments before the consumer sees safe output.
- Flow structure is still parsed by a recursive grammar nested in `YAMLFlowScanner`, with `YAMLFlowTokenBuffer` used for ambiguous sequence candidates and mapping keys.
- The current `YAMLFlowByteSource` / `YAMLFlowByteView` machinery exists to support the stopgap grammar. Once lexing and structural assembly are split, most of it becomes dead code.
- Comments and root `TODO.md` still describe the lexer/structure split as future work. After this plan, docs should describe the split as the active production architecture.

## File Map

- Create `Sources/Solid/YAML/YAMLFlowLexToken.swift`
  - Internal lexical token model for flow punctuation, decorators, aliases, scalars, line breaks, and EOF.
- Create `Sources/Solid/YAML/YAMLFlowLexer.swift`
  - Byte/range scanner that accepts retained line regions incrementally and appends `YAMLFlowLexToken` values.
- Create `Sources/Solid/YAML/YAMLFlowStructureAdapter.swift`
  - Structural adapter that consumes lexical tokens, tracks sequence/mapping frames, handles lookahead, and appends `YAMLRawToken` values.
- Modify `Sources/Solid/YAML/YAMLTokenizer.swift`
  - Replace `PendingFlow(scanner: YAMLFlowScanner, ...)` with `PendingFlow(lexer: YAMLFlowLexer, adapter: YAMLFlowStructureAdapter, ...)`.
  - Route `appendFlowTokens`, `appendCopiedFlowTokens`, and `finishPendingFlow` through the new split.
  - Delete stopgap-only flow types and comments after cutover.
- Modify `Tests/SolidYAMLTests/YAMLTokenizerTests.swift`
  - Replace "waits for balanced input" characterization with streaming-safe emission tests.
  - Preserve existing yaml-test-suite parity and replay-buffer regression tests as compatibility tests.
- Modify `TODO.md`
  - Move the lexer/structure split from future work to completed architecture notes after cutover.
- Modify `docs/superpowers/plans/2026-04-30-yaml-byte-range-cleanup-performance-docs.md`
  - Add a status note that the stopgap plan has been superseded by this split.

## Non-Goals

- Do not change `YAMLRawToken`, `YAMLRawScalar`, `ParseEvent`, `EmitEvent`, or reader/writer public APIs.
- Do not rewrite the block-line tokenizer in this pass.
- Do not remove `String` conversion from quoted scalar normalization, tag decoding, anchors, aliases, or directive payloads where the model requires `String`.
- Do not change YAML node/event-suite rendering semantics.

---

### Task 1: Add Streaming Behavior Tests For Flow Tokens

**Files:**
- Modify: `Tests/SolidYAMLTests/YAMLTokenizerTests.swift`

- [ ] **Step 1: Replace the old balanced-input expectation with earlier safe emission**

Find the existing test named:

```swift
@Test("flow scanner waits for balanced input before emitting tokens")
func flowScannerWaitsForBalancedInput() throws
```

Replace it with:

```swift
@Test("flow tokenizer emits safe tokens before the full flow collection closes")
func flowTokenizerEmitsSafeTokensBeforeCollectionCloses() throws {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data("[a, ".utf8), isFinal: false)

  try expectDocumentStart(try tokenizer.readToken(), explicit: false)
  try expectBeginSequence(try tokenizer.readToken(), style: .flow)
  try expectRetainedScalar(try tokenizer.readToken(), text: "a")
  #expect(try tokenizer.readToken() == nil)

  tokenizer.feedInput(Data("{b: c}".utf8), isFinal: false)
  try expectBeginMapping(try tokenizer.readToken(), style: .flow)
  try expectRetainedScalar(try tokenizer.readToken(), text: "b")
  try expectRetainedScalar(try tokenizer.readToken(), text: "c")
  try expectEndMapping(try tokenizer.readToken())
  #expect(try tokenizer.readToken() == nil)

  tokenizer.feedInput(Data("]\n".utf8), isFinal: true)
  try expectEndSequence(try tokenizer.readToken())
  try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
  #expect(try tokenizer.readToken() == nil)
}
```

- [ ] **Step 2: Add a test for delayed ambiguous sequence item emission**

Add this test near the flow replay-buffer tests:

```swift
@Test("flow tokenizer delays only ambiguous sequence candidates")
func flowTokenizerDelaysOnlyAmbiguousSequenceCandidates() throws {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data("[foo".utf8), isFinal: false)

  try expectDocumentStart(try tokenizer.readToken(), explicit: false)
  try expectBeginSequence(try tokenizer.readToken(), style: .flow)
  #expect(try tokenizer.readToken() == nil)

  tokenizer.feedInput(Data(", bar]\n".utf8), isFinal: true)
  try expectRetainedScalar(try tokenizer.readToken(), text: "foo")
  try expectRetainedScalar(try tokenizer.readToken(), text: "bar")
  try expectEndSequence(try tokenizer.readToken())
  try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
  #expect(try tokenizer.readToken() == nil)
}
```

This captures the intended compromise: the adapter can emit collection starts immediately, but a plain sequence candidate remains pending until `:`, `,`, or close decides whether it is an implicit mapping pair.

- [ ] **Step 3: Add a test for implicit mapping conversion across chunks**

Add:

```swift
@Test("flow tokenizer converts ambiguous candidate to mapping across chunks")
func flowTokenizerConvertsAmbiguousCandidateToMappingAcrossChunks() throws {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data("[foo".utf8), isFinal: false)

  try expectDocumentStart(try tokenizer.readToken(), explicit: false)
  try expectBeginSequence(try tokenizer.readToken(), style: .flow)
  #expect(try tokenizer.readToken() == nil)

  tokenizer.feedInput(Data(": bar]\n".utf8), isFinal: true)
  try expectBeginMapping(try tokenizer.readToken(), style: .flow)
  try expectRetainedScalar(try tokenizer.readToken(), text: "foo")
  try expectRetainedScalar(try tokenizer.readToken(), text: "bar")
  try expectEndMapping(try tokenizer.readToken())
  try expectEndSequence(try tokenizer.readToken())
  try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
  #expect(try tokenizer.readToken() == nil)
}
```

- [ ] **Step 4: Run the new tests and verify they fail before implementation**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests/flowTokenizer
```

Expected: FAIL because the current stopgap emits no flow tokens until the collection is balanced.

---

### Task 2: Add Flow Lexical Token Types

**Files:**
- Create: `Sources/Solid/YAML/YAMLFlowLexToken.swift`

- [ ] **Step 1: Add the lexical token model**

Create `Sources/Solid/YAML/YAMLFlowLexToken.swift`:

```swift
import Foundation

enum YAMLFlowLexToken: Sendable {
  case beginSequence(YAML.ParseError.Location)
  case endSequence(YAML.ParseError.Location)
  case beginMapping(YAML.ParseError.Location)
  case endMapping(YAML.ParseError.Location)
  case comma(YAML.ParseError.Location)
  case colon(YAML.ParseError.Location)
  case explicitKey(YAML.ParseError.Location)
  case scalar(YAMLRawScalar, YAML.ParseError.Location)
  case tag(String, YAML.ParseError.Location)
  case anchor(String, YAML.ParseError.Location)
  case alias(String, YAML.ParseError.Location)
  case lineBreak(YAML.ParseError.Location)
  case endOfInput(YAML.ParseError.Location)

  var location: YAML.ParseError.Location {
    switch self {
    case .beginSequence(let location),
      .endSequence(let location),
      .beginMapping(let location),
      .endMapping(let location),
      .comma(let location),
      .colon(let location),
      .explicitKey(let location),
      .scalar(_, let location),
      .tag(_, let location),
      .anchor(_, let location),
      .alias(_, let location),
      .lineBreak(let location),
      .endOfInput(let location):
      return location
    }
  }
}

struct YAMLFlowLexTokenQueue: Sendable {
  private var storage: ContiguousArray<YAMLFlowLexToken> = []
  private var head = 0

  var isEmpty: Bool { head >= storage.count }

  mutating func append(_ token: YAMLFlowLexToken) {
    storage.append(token)
  }

  mutating func peek() -> YAMLFlowLexToken? {
    guard head < storage.count else { return nil }
    return storage[head]
  }

  mutating func pop() -> YAMLFlowLexToken? {
    guard head < storage.count else { return nil }
    defer {
      head += 1
      compactIfNeeded()
    }
    return storage[head]
  }

  private mutating func compactIfNeeded() {
    guard head > 32, head * 2 > storage.count else { return }
    storage.removeFirst(head)
    head = 0
  }
}
```

- [ ] **Step 2: Build to verify new file is compiled**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift build --disable-sandbox
```

Expected: PASS.

---

### Task 3: Add Incremental `YAMLFlowLexer`

**Files:**
- Create: `Sources/Solid/YAML/YAMLFlowLexer.swift`
- Modify: `Sources/Solid/YAML/YAMLTokenizer.swift`

- [ ] **Step 1: Move reusable flow byte helpers out of `YAMLTokenizer.swift`**

Move these helper routines from the nested `YAMLFlowScanner.Grammar` area into `YAMLFlowLexer.swift` as file-private helpers:

```swift
private func yamlFlowIsDecoratorByte(_ byte: UInt8) -> Bool {
  !byte.isYAMLWhitespace
    && byte != .comma
    && byte != .leftSquare
    && byte != .rightSquare
    && byte != .leftBrace
    && byte != .rightBrace
}

private func yamlFlowTrimHorizontalAndNewlineBytes(
  _ bytes: UnsafeBufferPointer<UInt8>,
  in range: Range<Int>
) -> Range<Int> {
  var lower = range.lowerBound
  var upper = range.upperBound
  while lower < upper, bytes[lower].isYAMLWhitespace {
    lower += 1
  }
  while upper > lower, bytes[upper - 1].isYAMLWhitespace {
    upper -= 1
  }
  return lower..<upper
}
```

Do not delete the old nested helpers yet; the old stopgap still compiles until Task 6.

- [ ] **Step 2: Add the lexer skeleton**

Create `Sources/Solid/YAML/YAMLFlowLexer.swift`:

```swift
import Foundation

struct YAMLFlowLexer: ~Copyable, Sendable {
  private var tagHandles: [String: String]
  private var location: YAML.ParseError.Location
  private var pendingGeneratedScalarBytes = Data()

  init(tagHandles: [String: String], location: YAML.ParseError.Location) {
    self.tagHandles = tagHandles
    self.location = location
  }

  mutating func updateTagHandles(_ tagHandles: [String: String]) {
    self.tagHandles = tagHandles
  }

  mutating func feedLine(
    _ region: ParseBuffer.Region,
    leadingNewline: Bool,
    into queue: inout YAMLFlowLexTokenQueue
  ) throws {
    if leadingNewline {
      queue.append(.lineBreak(location))
    }
    try region.withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      try scan(bytes: bytes, sourceRegion: region, into: &queue)
    }
  }

  mutating func feedGeneratedBytes(
    _ data: Data,
    sourceRegion: ParseBuffer.Region?,
    leadingNewline: Bool,
    into queue: inout YAMLFlowLexTokenQueue
  ) throws {
    if leadingNewline {
      queue.append(.lineBreak(location))
    }
    try data.withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      try scan(bytes: bytes, sourceRegion: sourceRegion, into: &queue)
    }
  }

  mutating func finish(into queue: inout YAMLFlowLexTokenQueue) {
    queue.append(.endOfInput(location))
  }

  private mutating func scan(
    bytes: UnsafeBufferPointer<UInt8>,
    sourceRegion: ParseBuffer.Region?,
    into queue: inout YAMLFlowLexTokenQueue
  ) throws {
    var index = bytes.startIndex
    while index < bytes.endIndex {
      let byte = bytes[index]
      switch byte {
      case .space, .tab, .newline, .carriageReturn:
        index += 1
      case .leftSquare:
        queue.append(.beginSequence(location))
        index += 1
      case .rightSquare:
        queue.append(.endSequence(location))
        index += 1
      case .leftBrace:
        queue.append(.beginMapping(location))
        index += 1
      case .rightBrace:
        queue.append(.endMapping(location))
        index += 1
      case .comma:
        queue.append(.comma(location))
        index += 1
      case .colon:
        queue.append(.colon(location))
        index += 1
      case .question:
        queue.append(.explicitKey(location))
        index += 1
      case .exclamation:
        let parsed = try parseTag(bytes: bytes, start: index)
        queue.append(.tag(parsed.tag, location))
        index = parsed.end
      case .ampersand:
        let parsed = try parseAnchor(bytes: bytes, start: index)
        queue.append(.anchor(parsed.anchor, location))
        index = parsed.end
      case .asterisk:
        let parsed = try parseAlias(bytes: bytes, start: index)
        queue.append(.alias(parsed.alias, location))
        index = parsed.end
      case .singleQuote:
        let parsed = try parseSingleQuoted(bytes: bytes, start: index)
        queue.append(.scalar(parsed.scalar, location))
        index = parsed.end
      case .doubleQuote:
        let parsed = try parseDoubleQuoted(bytes: bytes, start: index)
        queue.append(.scalar(parsed.scalar, location))
        index = parsed.end
      case .comment:
        while index < bytes.endIndex, !bytes[index].isYAMLLineBreak {
          index += 1
        }
      default:
        let parsed = parsePlainScalar(bytes: bytes, sourceRegion: sourceRegion, start: index)
        if parsed.scalar.region.isEmpty {
          throw YAML.ParseError.invalidSyntax("Expected flow node", location: location)
        }
        queue.append(.scalar(parsed.scalar, location))
        index = parsed.end
      }
    }
  }
}
```

- [ ] **Step 3: Add exact scalar parsing helpers to the lexer**

Port the existing `YAMLFlowScanner.Grammar` helpers into `YAMLFlowLexer` with these signatures:

```swift
private mutating func parseTag(
  bytes: UnsafeBufferPointer<UInt8>,
  start: Int
) throws -> (tag: String, end: Int)

private mutating func parseAnchor(
  bytes: UnsafeBufferPointer<UInt8>,
  start: Int
) throws -> (anchor: String, end: Int)

private mutating func parseAlias(
  bytes: UnsafeBufferPointer<UInt8>,
  start: Int
) throws -> (alias: String, end: Int)

private mutating func parsePlainScalar(
  bytes: UnsafeBufferPointer<UInt8>,
  sourceRegion: ParseBuffer.Region?,
  start: Int
) -> (scalar: YAMLRawScalar, end: Int)

private mutating func parseSingleQuoted(
  bytes: UnsafeBufferPointer<UInt8>,
  start: Int
) throws -> (scalar: YAMLRawScalar, end: Int)

private mutating func parseDoubleQuoted(
  bytes: UnsafeBufferPointer<UInt8>,
  start: Int
) throws -> (scalar: YAMLRawScalar, end: Int)
```

Use the existing behavior:

- Plain same-line scalar with `sourceRegion != nil` returns `sourceRegion.subregion(...)`.
- Plain multiline/generated scalar returns `ParseBuffer.Region(data: foldedData)`.
- Quoted scalars return generated `.string` regions because escapes/folding normalize bytes.
- Tag/anchor/alias payloads remain `String`.

- [ ] **Step 4: Build after adding lexer**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift build --disable-sandbox
```

Expected: PASS. The lexer may not yet be wired into production.

---

### Task 4: Add `YAMLFlowStructureAdapter`

**Files:**
- Create: `Sources/Solid/YAML/YAMLFlowStructureAdapter.swift`

- [ ] **Step 1: Add adapter frame and node buffer types**

Create `Sources/Solid/YAML/YAMLFlowStructureAdapter.swift`:

```swift
import Foundation

struct YAMLFlowStructureAdapter: Sendable {
  private enum Frame: Sendable {
    case sequence(expectingItem: Bool)
    case mapping(expectingKey: Bool)
  }

  private struct PendingNode: Sendable {
    var tokens: ContiguousArray<YAMLRawToken> = []

    var isEmpty: Bool { tokens.isEmpty }

    mutating func append(_ token: YAMLRawToken) {
      tokens.append(token)
    }

    func replay(into output: inout YAMLTokenizer.PendingTokenQueue) {
      for token in tokens {
        output.append(token)
      }
    }
  }

  private var frames: ContiguousArray<Frame> = []
  private var pendingDecorators: ContiguousArray<YAMLRawToken> = []
  private var pendingSequenceCandidate: PendingNode?

  mutating func consume(
    _ token: YAMLFlowLexToken,
    output: inout YAMLTokenizer.PendingTokenQueue
  ) throws {
    switch token {
    case .beginSequence:
      try flushPendingSequenceCandidate(asMapping: false, output: &output)
      output.append(.beginSequence(style: .flow))
      frames.append(.sequence(expectingItem: true))
    case .endSequence:
      try closeSequence(output: &output)
    case .beginMapping:
      try flushPendingSequenceCandidate(asMapping: false, output: &output)
      output.append(.beginMapping(style: .flow))
      frames.append(.mapping(expectingKey: true))
    case .endMapping:
      try closeMapping(output: &output)
    case .comma:
      try endEntry(output: &output)
    case .colon:
      try convertPendingCandidateToMapping(output: &output)
    case .explicitKey:
      try startExplicitEntry(output: &output)
    case .scalar(let scalar, _):
      try appendNodeToken(.scalar(scalar), output: &output)
    case .tag(let tag, _):
      pendingDecorators.append(.tag(tag))
    case .anchor(let anchor, _):
      pendingDecorators.append(.anchor(anchor))
    case .alias(let alias, _):
      try appendNodeToken(.alias(alias), output: &output)
    case .lineBreak:
      return
    case .endOfInput(let location):
      try finish(location: location, output: &output)
    }
  }
}
```

- [ ] **Step 2: Implement node append and decorator replay**

Add these methods inside `YAMLFlowStructureAdapter`:

```swift
private mutating func appendNodeToken(
  _ token: YAMLRawToken,
  output: inout YAMLTokenizer.PendingTokenQueue
) throws {
  var node = PendingNode()
  for decorator in pendingDecorators {
    node.append(decorator)
  }
  pendingDecorators.removeAll(keepingCapacity: true)
  node.append(token)

  if case .sequence = frames.last {
    pendingSequenceCandidate = node
    return
  }

  node.replay(into: &output)
  if case .mapping(let expectingKey) = frames.last {
    frames.removeLast()
    frames.append(.mapping(expectingKey: !expectingKey))
  }
}
```

If the current frame is a mapping expecting a key, the scalar/alias is the key; if expecting value, it is the value. The adapter should flip the mapping state after replaying the node.

- [ ] **Step 3: Implement explicit/empty entry handling**

Add methods:

```swift
private mutating func appendEmptyScalar(into output: inout YAMLTokenizer.PendingTokenQueue) {
  output.append(.scalar(.init(
    style: .plain,
    kind: .number,
    region: .init(data: Data())
  )))
}

private mutating func startExplicitEntry(output: inout YAMLTokenizer.PendingTokenQueue) throws {
  try flushPendingSequenceCandidate(asMapping: false, output: &output)
  output.append(.beginMapping(style: .flow))
  frames.append(.mapping(expectingKey: true))
}
```

- [ ] **Step 4: Implement close and finish behavior**

Add:

```swift
private mutating func closeSequence(output: inout YAMLTokenizer.PendingTokenQueue) throws {
  try flushPendingSequenceCandidate(asMapping: false, output: &output)
  guard let frame = frames.popLast(), case .sequence = frame else {
    throw YAML.ParseError.invalidSyntax("Unexpected flow sequence close", location: .init(line: 1, column: 1))
  }
  output.append(.endSequence)
}

private mutating func closeMapping(output: inout YAMLTokenizer.PendingTokenQueue) throws {
  try flushPendingSequenceCandidate(asMapping: false, output: &output)
  guard let frame = frames.popLast(), case .mapping = frame else {
    throw YAML.ParseError.invalidSyntax("Unexpected flow mapping close", location: .init(line: 1, column: 1))
  }
  output.append(.endMapping)
}

private mutating func finish(
  location: YAML.ParseError.Location,
  output: inout YAMLTokenizer.PendingTokenQueue
) throws {
  try flushPendingSequenceCandidate(asMapping: false, output: &output)
  guard frames.isEmpty else {
    throw YAML.ParseError.incompleteInput(location: location)
  }
}
```

After this step, replace the hard-coded `.init(line: 1, column: 1)` in close errors by threading the current token location into `closeSequence` and `closeMapping`.

- [ ] **Step 5: Implement candidate conversion**

Add:

```swift
private mutating func convertPendingCandidateToMapping(
  output: inout YAMLTokenizer.PendingTokenQueue
) throws {
  guard let candidate = pendingSequenceCandidate else {
    appendEmptyScalar(into: &output)
    return
  }
  pendingSequenceCandidate = nil
  output.append(.beginMapping(style: .flow))
  candidate.replay(into: &output)
}

private mutating func flushPendingSequenceCandidate(
  asMapping: Bool,
  output: inout YAMLTokenizer.PendingTokenQueue
) throws {
  guard let candidate = pendingSequenceCandidate else {
    return
  }
  pendingSequenceCandidate = nil
  if asMapping {
    output.append(.beginMapping(style: .flow))
  }
  candidate.replay(into: &output)
  if asMapping {
    appendEmptyScalar(into: &output)
    output.append(.endMapping)
  }
}
```

Then update `endEntry(output:)` to finish an implicit mapping pair if a colon converted the candidate, or replay the pending sequence item if the delimiter is `,`/`]`.

- [ ] **Step 6: Build adapter**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift build --disable-sandbox
```

Expected: PASS. The adapter may still be incomplete for edge cases until wiring and parity tasks.

---

### Task 5: Wire Lexer / Adapter Into `YAMLTokenizer`

**Files:**
- Modify: `Sources/Solid/YAML/YAMLTokenizer.swift`

- [ ] **Step 1: Replace `PendingFlow` shape**

Replace:

```swift
private struct PendingFlow: ~Copyable, Sendable {
  var scanner: YAMLFlowScanner
  let opener: UInt8
  let minimumContinuationIndent: Int?
}
```

with:

```swift
private struct PendingFlow: ~Copyable, Sendable {
  var lexer: YAMLFlowLexer
  var adapter: YAMLFlowStructureAdapter
  var lexTokens = YAMLFlowLexTokenQueue()
  let opener: UInt8
  let minimumContinuationIndent: Int?
}
```

- [ ] **Step 2: Add a token-drain helper**

Add this method near `finishPendingFlow()`:

```swift
private mutating func drainPendingFlowLexTokens() throws {
  guard pendingFlow != nil else { return }
  while let token = pendingFlow!.lexTokens.pop() {
    try pendingFlow!.adapter.consume(token, output: &pendingTokens)
  }
}
```

- [ ] **Step 3: Rewrite `appendFlowTokens` to feed lexer lines**

Replace the current scanner creation in `appendFlowTokens(_ region:location:minimumContinuationIndent:)` with:

```swift
var lexer = YAMLFlowLexer(tagHandles: tagHandles, location: location)
var lexTokens = YAMLFlowLexTokenQueue()
try lexer.feedLine(region, leadingNewline: false, into: &lexTokens)
var adapter = YAMLFlowStructureAdapter()
pendingFlow = PendingFlow(
  lexer: lexer,
  adapter: adapter,
  lexTokens: lexTokens,
  opener: region.firstByte ?? .leftSquare,
  minimumContinuationIndent: minimumContinuationIndent
)
try drainPendingFlowLexTokens()
if pendingFlow?.lexTokens.isEmpty == true, isFlowCloseLine(region, opener: pendingFlow?.opener ?? .leftSquare) {
  try finishPendingFlow()
}
```

Keep the existing `markDocumentContent()` call after successful flow token emission.

- [ ] **Step 4: Rewrite multiline flow continuation to feed retained regions**

Where current code calls `pendingFlow!.scanner.feedLine(...)`, replace it with:

```swift
try pendingFlow!.lexer.feedLine(
  region,
  leadingNewline: true,
  into: &pendingFlow!.lexTokens
)
try drainPendingFlowLexTokens()
```

For generated/copied flow bytes, replace scanner data feeding with:

```swift
try pendingFlow!.lexer.feedGeneratedBytes(
  data,
  sourceRegion: sourceRegion,
  leadingNewline: true,
  into: &pendingFlow!.lexTokens
)
try drainPendingFlowLexTokens()
```

- [ ] **Step 5: Rewrite `finishPendingFlow`**

Replace:

```swift
try pendingFlow!.scanner.finish(tagHandles: tagHandles, into: &pendingTokens)
```

with:

```swift
pendingFlow!.lexer.finish(into: &pendingFlow!.lexTokens)
try drainPendingFlowLexTokens()
```

Then clear `pendingFlow` and call `markDocumentContent()` as today.

- [ ] **Step 6: Run the streaming flow tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests/flowTokenizer
```

Expected: PASS for the three tests added in Task 1.

---

### Task 6: Preserve Flow Semantics And Edge-Case Parity

**Files:**
- Modify: `Sources/Solid/YAML/YAMLFlowStructureAdapter.swift`
- Modify: `Sources/Solid/YAML/YAMLFlowLexer.swift`
- Modify: `Tests/SolidYAMLTests/YAMLTokenizerTests.swift`

- [ ] **Step 1: Run all existing flow-focused tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests/flow
```

Expected initially: failures in edge cases the adapter has not yet matched.

- [ ] **Step 2: Add an explicit test for decorators on ambiguous flow keys**

Add:

```swift
@Test("flow lexer adapter preserves decorators on ambiguous mapping keys")
func flowLexerAdapterPreservesDecoratorsOnAmbiguousMappingKeys() throws {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data("[!tag &a key: *a]\n".utf8), isFinal: true)

  try expectDocumentStart(try tokenizer.readToken(), explicit: false)
  try expectBeginSequence(try tokenizer.readToken(), style: .flow)
  try expectBeginMapping(try tokenizer.readToken(), style: .flow)
  try expectTag(try tokenizer.readToken(), "!tag")
  try expectAnchor(try tokenizer.readToken(), "a")
  try expectRetainedScalar(try tokenizer.readToken(), text: "key")
  try expectAlias(try tokenizer.readToken(), "a")
  try expectEndMapping(try tokenizer.readToken())
  try expectEndSequence(try tokenizer.readToken())
  try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
  #expect(try tokenizer.readToken() == nil)
}
```

- [ ] **Step 3: Add an explicit test for complex flow keys**

Add:

```swift
@Test("flow lexer adapter preserves complex keys")
func flowLexerAdapterPreservesComplexKeys() throws {
  try assertSingleDocumentTokens("[[a]: b, {c: d}: e]\n") { tokenizer in
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)
    try expectBeginMapping(try tokenizer.readToken(), style: .flow)
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)
    try expectRetainedScalar(try tokenizer.readToken(), text: "a")
    try expectEndSequence(try tokenizer.readToken())
    try expectRetainedScalar(try tokenizer.readToken(), text: "b")
    try expectEndMapping(try tokenizer.readToken())
    try expectBeginMapping(try tokenizer.readToken(), style: .flow)
    try expectBeginMapping(try tokenizer.readToken(), style: .flow)
    try expectRetainedScalar(try tokenizer.readToken(), text: "c")
    try expectRetainedScalar(try tokenizer.readToken(), text: "d")
    try expectEndMapping(try tokenizer.readToken())
    try expectRetainedScalar(try tokenizer.readToken(), text: "e")
    try expectEndMapping(try tokenizer.readToken())
    try expectEndSequence(try tokenizer.readToken())
  }
}
```

- [ ] **Step 4: Fix adapter edge cases until flow tests pass**

Use these adapter rules:

- In a sequence frame, a candidate followed by `:` becomes a single-entry flow mapping.
- In a sequence frame, a candidate followed by `,` or `]` is replayed as a normal item.
- In a mapping frame expecting a key, a candidate followed by `:` becomes the key.
- In a mapping frame expecting a key, `:` without a candidate emits an empty key.
- In a mapping frame expecting a value, `,`, `}`, or EOF emits an empty value.
- Explicit `?` starts a single flow mapping entry and missing key/value slots become empty scalars.
- Tags and anchors attach to the next node; aliases are nodes.

- [ ] **Step 5: Run flow-focused tests again**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests/flow
```

Expected: PASS.

- [ ] **Step 6: Run YAML tokenizer suite**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
```

Expected: PASS.

---

### Task 7: Delete Stopgap Flow Parser Code

**Files:**
- Modify: `Sources/Solid/YAML/YAMLTokenizer.swift`

- [ ] **Step 1: Delete stopgap-only types from `YAMLTokenizer.swift`**

Remove these types after Task 6 passes:

```swift
private struct YAMLFlowSegment
private struct YAMLFlowByteSource
private struct YAMLFlowByteView
private struct YAMLFlowBalance
private protocol YAMLFlowTokenSink
private struct YAMLFlowTokenBuffer
private struct YAMLFlowScanner
```

Also remove nested `YAMLFlowScanner.Grammar` and its helper methods.

- [ ] **Step 2: Remove stopgap comments**

Remove the comment beginning:

```swift
// Stopgap architecture: retain incoming flow segments until the collection is
```

There should be no "stopgap" wording in production source after cutover.

- [ ] **Step 3: Run dead-code greps**

Run:

```bash
rg -n "YAMLFlowScanner|YAMLFlowSegment|YAMLFlowByteSource|YAMLFlowByteView|YAMLFlowBalance|YAMLFlowTokenBuffer|Stopgap architecture|recursive flow grammar|whole-flow" Sources/Solid/YAML
```

Expected: no output from `Sources/Solid/YAML`.

- [ ] **Step 4: Build**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift build --disable-sandbox
```

Expected: PASS.

---

### Task 8: Update Documentation And Comments

**Files:**
- Modify: `TODO.md`
- Modify: `Sources/Solid/YAML/YAMLTokenizer.swift`
- Modify: `Sources/Solid/YAML/YAMLEventReader.swift`
- Modify: `docs/superpowers/plans/2026-04-30-yaml-byte-range-cleanup-performance-docs.md`

- [ ] **Step 1: Update root `TODO.md`**

Replace the current `## SolidYAML` content with:

```markdown
## SolidYAML

### Completed: Split YAML Flow Lexing From Structural Event Assembly

Flow parsing now uses two internal stages:

1. `YAMLFlowLexer` emits lower-level lexical tokens from retained byte regions.
2. `YAMLFlowStructureAdapter` consumes those tokens with lookahead and emits `YAMLRawToken`.

Shape:

```text
YAML byte scanner
  -> YAML lexical tokens
  -> YAML structural adapter
  -> YAMLRawToken
  -> ParseEvent / YAMLNodeBuilder
```

Goals preserved:
- YAML ambiguity is isolated in the structural adapter instead of recursive flow parsing.
- Retained scalar regions survive through lexical tokens when bytes are unchanged.
- Lookahead for `:`, `,`, `]`, `}`, explicit `?`, empty keys/values, tags, anchors, and aliases is centralized.
- Recursive `ContiguousArray<YAMLRawToken>` buffering is removed from flow scanning.
```

- [ ] **Step 2: Update `YAMLTokenizer.swift` top comment**

Ensure the top comment describes the tokenizer as byte/range based and notes that flow uses lexer/structure split:

```swift
/// Incremental YAML tokenizer. Block lines are classified from retained
/// `ParseBuffer.Region` slices, while flow collections are split into lexical
/// tokens and structurally assembled into `YAMLRawToken` events.
```

- [ ] **Step 3: Add a status note to the old cleanup plan**

At the top of `docs/superpowers/plans/2026-04-30-yaml-byte-range-cleanup-performance-docs.md`, add:

```markdown
> Status note: Superseded by `2026-05-01-yaml-flow-lexer-structure-split.md`.
> The replay-buffer stopgap has been replaced by the lexer/structure split.
```

- [ ] **Step 4: Run documentation/source grep**

Run:

```bash
rg -n "future lexer/structure|Completed Stopgap|Stopgap architecture|recursive flow grammar expansion|YAMLFlowScanner" TODO.md Sources/Solid/YAML docs/superpowers/plans/2026-04-30-yaml-byte-range-cleanup-performance-docs.md
```

Expected:
- No hits in `Sources/Solid/YAML`.
- `TODO.md` describes completed lexer/structure split, not future work.
- Historical plan hits are acceptable only in status notes or old task bodies.

---

### Task 9: Final Verification

**Files:**
- No edits unless verification exposes a bug.

- [ ] **Step 1: Run YAML tokenizer tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
```

Expected: PASS.

- [ ] **Step 2: Run SolidYAML tests**

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

- [ ] **Step 4: Run final production grep**

Run:

```bash
rg -n "YAMLFlowScanner|YAMLFlowTokenBuffer|YAMLFlowByteView|YAMLFlowByteSource|YAMLFlowBalance|Stopgap architecture|whole-flow|materializedFlowBytes|flowBytesAreComplete|YAMLFlowParser|YAMLFlowTokenizer" Sources/Solid/YAML
```

Expected: no output.

- [ ] **Step 5: Review scoped diff**

Run:

```bash
git diff -- Sources/Solid/YAML/YAMLTokenizer.swift Sources/Solid/YAML/YAMLFlowLexToken.swift Sources/Solid/YAML/YAMLFlowLexer.swift Sources/Solid/YAML/YAMLFlowStructureAdapter.swift Tests/SolidYAMLTests/YAMLTokenizerTests.swift TODO.md docs/superpowers/plans/2026-04-30-yaml-byte-range-cleanup-performance-docs.md docs/superpowers/plans/2026-05-01-yaml-flow-lexer-structure-split.md
```

Expected:
- Public API unchanged.
- Flow parsing no longer retains the full collection until balanced before emitting safe tokens.
- Stopgap flow types removed from production source.
- Documentation matches the new flow lexer/structure adapter architecture.

---

## Self-Review Checklist

- [ ] Performance gap covered: flow collections can emit safe tokens incrementally instead of waiting for full balance.
- [ ] Functionality gap covered: YAML ambiguity is centralized in `YAMLFlowStructureAdapter`.
- [ ] Dead code covered: stopgap flow scanner, byte view, balance tracker, and replay buffer are deleted after cutover.
- [ ] Comments/docs covered: production comments and root `TODO.md` no longer describe lexer/structure split as future work.
- [ ] Public API preserved: no changes to `YAMLRawToken`, `YAMLRawScalar`, `ParseEvent`, `EmitEvent`, or reader/writer APIs.
- [ ] Verification commands included: tokenizer suite, SolidYAML suite, full package suite, and production grep.

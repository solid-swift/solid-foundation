# YAML Byte/Range Cleanup, Dead Code, and Documentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status, 2026-05-01:** This cleanup plan has been superseded by the YAML flow lexer/structure split. The replay-buffer stopgap described below is no longer the production architecture; flow parsing now uses `YAMLFlowLexer` plus `YAMLFlowStructureAdapter`, and the old whole-flow scanner/parser code has been removed.

**Goal:** Close the remaining YAML byte/range gaps that still affect performance or expected behavior, remove stale/dead code from the stopgap flow refactor, and update comments/docs so they match the current tokenizer architecture.

**Architecture:** Keep public APIs and `YAMLRawToken` output unchanged. Preserve the current Option 1 flow replay-buffer stopgap, but remove production whole-line `String` classification where it is not required for scalar normalization, tighten retained-region tests, and document that the larger lexer/structure split is deferred.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftPM, `ParseBuffer.Region`, `YAMLTokenizer`, `YAMLFlowScanner`, `PendingTokenQueue`, `ContiguousArray`.

---

## File Map

- Modify `Sources/Solid/YAML/YAMLTokenizer.swift`
  - Remove the remaining `isDocumentBoundary(_ text: String)` production fallback by checking pending quoted-scalar continuation lines with byte/range helpers before converting to `String`.
  - Keep `String` conversion in quoted-scalar normalization, tag/directive payloads, anchors, aliases, and generated scalar output.
  - Update comments around `YAMLFlowScanner.emitIfComplete` and `YAMLFlowScanner.Grammar` to describe the current replay-buffer stopgap accurately.
  - Remove or narrow stale helper extensions if they become unused after the byte boundary check.
- Modify `Tests/SolidYAMLTests/YAMLTokenizerTests.swift`
  - Add regression coverage for pending quoted-scalar document-boundary errors without relying on whole-line `String` classification.
  - Add tests that protect current flow replay-buffer behavior and retained-region expectations while cleanup happens.
- Modify `TODO.md`
  - Mark the Option 1 replay-buffer stopgap as completed.
  - Keep the future lexer/structure split as the remaining long-term SolidYAML task.
- Modify docs under `docs/superpowers/plans/`
  - Add a short status note to the latest remaining-gaps plan or create a sibling note documenting what has been completed and what is intentionally deferred.

## Non-Goals

- Do not implement the future YAML lexical-token / structural-adapter split in this pass.
- Do not change `YAMLRawToken`, `YAMLRawScalar`, `ParseEvent`, `EmitEvent`, reader APIs, writer APIs, or public `YAMLNode` shapes.
- Do not remove `String` use from quoted scalar normalization; YAML quoted scalars inherently normalize escapes and folded line breaks into new bytes.
- Do not add broad `@inlinable` or `InlineArray` changes without benchmark evidence.

---

### Task 1: Characterize Remaining Quoted-Scalar Boundary Behavior

**Files:**
- Modify: `Tests/SolidYAMLTests/YAMLTokenizerTests.swift`

- [ ] **Step 1: Add tests for document markers inside pending quoted scalars**

Add these tests near the existing quoted trailing whitespace / multiline quoted scalar tests:

```swift
@Test("document start marker is rejected inside multiline quoted scalar continuation")
func documentStartMarkerRejectedInsidePendingQuotedScalar() throws {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data("\"open\n---\n".utf8), isFinal: true)

  try expectDocumentStart(try tokenizer.readToken(), explicit: false)
  #expect(throws: YAML.ParseError.self) {
    _ = try tokenizer.readToken()
  }
}

@Test("document end marker is rejected inside multiline quoted scalar continuation")
func documentEndMarkerRejectedInsidePendingQuotedScalar() throws {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data("'open\n...\n".utf8), isFinal: true)

  try expectDocumentStart(try tokenizer.readToken(), explicit: false)
  #expect(throws: YAML.ParseError.self) {
    _ = try tokenizer.readToken()
  }
}
```

- [ ] **Step 2: Add a positive control for quoted continuation text that only looks marker-like**

Add:

```swift
@Test("quoted scalar continuation keeps marker-looking content when not a boundary")
func quotedContinuationAllowsMarkerLikeText() throws {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data("\"open\n---value\"\n".utf8), isFinal: true)

  try expectDocumentStart(try tokenizer.readToken(), explicit: false)
  try expectScalarText(try tokenizer.readToken(), "open ---value")
  try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
  #expect(try tokenizer.readToken() == nil)
}
```

If `expectScalarText` is not available in this file, add:

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

- [ ] **Step 3: Run the focused tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
```

Expected: PASS before implementation. These are characterization tests for behavior that must survive removing the `String` boundary helper.

---

### Task 2: Replace Pending Quoted-Scalar Boundary Check With Region Bytes

**Files:**
- Modify: `Sources/Solid/YAML/YAMLTokenizer.swift`

- [ ] **Step 1: Add a byte/range helper for document-boundary checks on raw continuation regions**

Near the existing region document-boundary helpers, add:

```swift
private func isDocumentBoundaryAfterQuotedTrailingWhitespace(
  region: ParseBuffer.Region,
  quotedTrailingWhitespace: YAMLQuotedTrailingWhitespace
) -> Bool {
  if quotedTrailingWhitespace.isEmpty {
    return isDocumentBoundary(region.trimmedHorizontalWhitespace())
  }

  return region.withUnsafeBytes { rawBuffer in
    let bytes = rawBuffer.bindMemory(to: UInt8.self)
    var end = bytes.count
    while end > 0, bytes[end - 1].isYAMLHorizontalWhitespace {
      end -= 1
    }
    if end == 3,
      bytes[0] == .dash,
      bytes[1] == .dash,
      bytes[2] == .dash
    {
      return true
    }
    if end == 3,
      bytes[0] == UInt8(ascii: "."),
      bytes[1] == UInt8(ascii: "."),
      bytes[2] == UInt8(ascii: ".")
    {
      return true
    }
    if end > 3,
      bytes[0] == .dash,
      bytes[1] == .dash,
      bytes[2] == .dash,
      bytes[3].isYAMLWhitespace
    {
      return true
    }
    if end > 3,
      bytes[0] == UInt8(ascii: "."),
      bytes[1] == UInt8(ascii: "."),
      bytes[2] == UInt8(ascii: "."),
      bytes[3].isYAMLWhitespace
    {
      return true
    }
    return false
  }
}
```

This helper intentionally checks the original retained region before quoted whitespace is appended into the normalized scalar text. The boundary rule depends on the line content, not on the normalized scalar output.

- [ ] **Step 2: Update the pending quoted scalar continuation path**

Replace this shape in `processLine`:

```swift
let text = try appendQuotedTrailingWhitespace(
  quotedTrailingWhitespace,
  to: try region.string(),
  style: pendingQuotedScalar?.style
)
if indent == 0, isDocumentBoundary(text.yamlTrimmedHorizontalWhitespace) {
  throw YAML.ParseError.invalidSyntax(
    "Document marker is not allowed in quoted scalar",
    location: .init(line: line, column: indent + 1)
  )
}
```

with:

```swift
if indent == 0,
  isDocumentBoundaryAfterQuotedTrailingWhitespace(
    region: region,
    quotedTrailingWhitespace: quotedTrailingWhitespace
  )
{
  throw YAML.ParseError.invalidSyntax(
    "Document marker is not allowed in quoted scalar",
    location: .init(line: line, column: indent + 1)
  )
}

let text = try appendQuotedTrailingWhitespace(
  quotedTrailingWhitespace,
  to: try region.string(),
  style: pendingQuotedScalar?.style
)
```

This moves the document-boundary classification to retained bytes. The later `region.string()` remains allowed because the line is now known to be part of quoted scalar normalization.

- [ ] **Step 3: Remove dead `isDocumentBoundary(_ text: String)` if no longer referenced**

Run:

```bash
rg -n "isDocumentBoundary\\(_ text|isDocumentBoundary\\([^r]" Sources/Solid/YAML/YAMLTokenizer.swift
```

If the only `String` overload reference is its declaration, delete:

```swift
private func isDocumentBoundary(_ text: String) -> Bool {
  if text == "..." {
    return true
  }
  if text.hasPrefix("---") {
    let markerEnd = text.index(text.startIndex, offsetBy: 3)
    return markerEnd == text.endIndex || text[markerEnd].isWhitespace
  }
  if text.hasPrefix("...") {
    let markerEnd = text.index(text.startIndex, offsetBy: 3)
    return markerEnd == text.endIndex || text[markerEnd].isWhitespace
  }
  return false
}
```

- [ ] **Step 4: Run YAML tokenizer tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
```

Expected: PASS.

---

### Task 3: Remove Or Fence Remaining String-Only Helper Drift

**Files:**
- Modify: `Sources/Solid/YAML/YAMLTokenizer.swift`

- [ ] **Step 1: Audit broad String trimming usage**

Run:

```bash
rg -n "yamlTrimmedHorizontalWhitespace|trimmingCharacters\\(|stripSeparatedLineComment|decodeRegionString" Sources/Solid/YAML/YAMLTokenizer.swift
```

Expected after Task 2:
- No `stripSeparatedLineComment` hits.
- No `decodeRegionString` hits.
- `yamlTrimmedHorizontalWhitespace` may remain only in quoted scalar normalization helpers such as `validTrailingQuotedScalarContent`.
- No `trimmingCharacters(` production line-classification hits.

- [ ] **Step 2: Rename the remaining StringProtocol helper if it is quoted-only**

If `yamlTrimmedHorizontalWhitespace` is only used by quoted scalar normalization, rename it to make that scope explicit:

```swift
private extension StringProtocol {
  var yamlQuotedTrimmedHorizontalWhitespace: String {
    var lower = startIndex
    var upper = endIndex
    while lower < upper {
      let character = self[lower]
      guard character == " " || character == "\t" else { break }
      lower = index(after: lower)
    }
    while upper > lower {
      let previous = index(before: upper)
      let character = self[previous]
      guard character == " " || character == "\t" else { break }
      upper = previous
    }
    return String(self[lower..<upper])
  }
}
```

Update the quoted helper call site from:

```swift
let trailing = trailingContent.yamlTrimmedHorizontalWhitespace
```

to:

```swift
let trailing = trailingContent.yamlQuotedTrimmedHorizontalWhitespace
```

Do not keep both names.

- [ ] **Step 3: Verify the helper is not used for line classification**

Run:

```bash
rg -n "yamlTrimmedHorizontalWhitespace|yamlQuotedTrimmedHorizontalWhitespace" Sources/Solid/YAML/YAMLTokenizer.swift
```

Expected: only quoted scalar helper usage remains.

- [ ] **Step 4: Run YAML tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidYAML
```

Expected: PASS.

---

### Task 4: Tighten Flow Stopgap Comments And Guardrails

**Files:**
- Modify: `Sources/Solid/YAML/YAMLTokenizer.swift`
- Modify: `Tests/SolidYAMLTests/YAMLTokenizerTests.swift`

- [ ] **Step 1: Replace stale flow scanner comment**

Replace the comment in `YAMLFlowScanner.emitIfComplete`:

```swift
// Flow collections are emitted once structurally balanced so nested flow
// mapping/sequence edge cases keep the same event ordering as the YAML
// suite. The parser below still reads retained segments directly rather
// than materializing the whole flow collection first.
```

with:

```swift
// Stopgap architecture: retain incoming flow segments until the collection is
// balanced, then run one grammar pass over the retained byte view. The grammar
// emits directly into PendingTokenQueue and buffers only ambiguous sequence
// candidates that may become mapping pairs after ':'.
```

- [ ] **Step 2: Add a comment on `YAMLFlowTokenBuffer` explaining its narrow purpose**

Above `YAMLFlowTokenBuffer`, add:

```swift
/// Small replay buffer used only for YAML flow ambiguity. A sequence item must
/// be parsed before we know whether a following ':' turns it into a mapping
/// key. Do not use this as a general flow-token accumulator.
```

- [ ] **Step 3: Add a guard test for normal flow sequences that must not become mappings**

Add to `YAMLTokenizerTests` near `flowSequenceReplayBufferHandlesImplicitMappingCandidates`:

```swift
@Test("flow replay buffer preserves normal sequence items without colon")
func flowReplayBufferPreservesNormalSequenceItems() throws {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data("[foo, [bar], {baz: qux}]\n".utf8), isFinal: true)

  try expectDocumentStart(try tokenizer.readToken(), explicit: false)
  try expectBeginSequence(try tokenizer.readToken(), style: .flow)
  try expectScalarText(try tokenizer.readToken(), "foo")
  try expectBeginSequence(try tokenizer.readToken(), style: .flow)
  try expectScalarText(try tokenizer.readToken(), "bar")
  try expectEndSequence(try tokenizer.readToken())
  try expectBeginMapping(try tokenizer.readToken(), style: .flow)
  try expectScalarText(try tokenizer.readToken(), "baz")
  try expectScalarText(try tokenizer.readToken(), "qux")
  try expectEndMapping(try tokenizer.readToken())
  try expectEndSequence(try tokenizer.readToken())
  try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
  #expect(try tokenizer.readToken() == nil)
}
```

- [ ] **Step 4: Run tokenizer tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
```

Expected: PASS.

---

### Task 5: Update TODO And Plan Documentation

**Files:**
- Modify: `TODO.md`
- Modify: `docs/superpowers/plans/2026-04-30-yaml-byte-range-remaining-gaps.md`

- [ ] **Step 1: Update `TODO.md` with current stopgap status**

In `TODO.md`, keep the existing future SolidYAML task and append:

```markdown
### Completed Stopgap: Flow Replay Buffer

The current tokenizer keeps the public `YAMLRawToken` shape and uses a
replay buffer only for ambiguous flow sequence candidates. This avoids the old
whole-flow materialization gate while preserving behavior for implicit mapping
pairs such as `[foo: bar]`.

Remaining long-term work is the lexer/structure split above, not more ad hoc
recursive flow grammar expansion.
```

- [ ] **Step 2: Add a completion note to the old remaining-gaps plan**

At the top of `docs/superpowers/plans/2026-04-30-yaml-byte-range-remaining-gaps.md`, after the header, add:

```markdown
> Status note: The Option 1 stopgap has been implemented. `YAMLFlowScanner`
> now emits into `PendingTokenQueue` and uses a narrow replay buffer for
> ambiguous flow sequence candidates. The future lexer/structure split remains
> tracked in root `TODO.md`.
```

- [ ] **Step 3: Run a documentation grep for stale names**

Run:

```bash
rg -n "YAMLFlowParser|YAMLFlowTokenizer|flowBytesAreComplete|materializedFlowBytes|whole-flow materialization gate" TODO.md docs Sources/Solid/YAML/YAMLTokenizer.swift
```

Expected:
- No stale production references in `Sources/Solid/YAML/YAMLTokenizer.swift`.
- Historical plan references are acceptable only if marked as old context or status notes.

---

### Task 6: Final Cleanup Verification

**Files:**
- No edits unless verification exposes a missed stale reference.

- [ ] **Step 1: Run focused grep acceptance**

Run:

```bash
rg -n "decodeRegionString|stripSeparatedLineComment\\(|trimmingCharacters\\(|flowBytesAreComplete|materializedFlowBytes|YAMLFlowParser|YAMLFlowTokenizer|appendNodeText\\(" Sources/Solid/YAML/YAMLTokenizer.swift
```

Expected: no output.

- [ ] **Step 2: Run YAML tokenizer suite**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter YAMLTokenizerTests
```

Expected: PASS.

- [ ] **Step 3: Run SolidYAML suite**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox --filter SolidYAML
```

Expected: PASS.

- [ ] **Step 4: Run full suite**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --disable-sandbox
```

Expected: PASS.

- [ ] **Step 5: Review git diff for scope**

Run:

```bash
git diff -- TODO.md docs/superpowers/plans/2026-04-30-yaml-byte-range-remaining-gaps.md docs/superpowers/plans/2026-04-30-yaml-byte-range-cleanup-performance-docs.md Sources/Solid/YAML/YAMLTokenizer.swift Tests/SolidYAMLTests/YAMLTokenizerTests.swift
```

Expected:
- Code changes are limited to byte/range boundary cleanup, comments, and tests.
- No public API changes.
- No deletion of the future lexer/structure split task.

---

## Self-Review Checklist

- [ ] The plan addresses performance-impacting drift: pending quoted scalar boundary classification no longer uses a normalized `String` as the classifier.
- [ ] The plan addresses expected functionality: document marker errors inside quoted scalar continuation stay covered.
- [ ] The plan removes dead/stale code: `isDocumentBoundary(_ text:)` is removed if unused, and broad String helper naming is narrowed.
- [ ] The plan updates comments and documentation: `TODO.md` records the future lexer/structure split, while docs mark the replay-buffer stopgap as completed.
- [ ] The plan does not implement the deferred lexer/structure split.
- [ ] The plan includes exact test commands and grep acceptance checks.

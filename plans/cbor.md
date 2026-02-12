# CBOR Streaming Fixes Proposal

This plan targets two main gaps: (1) reader buffering/copying and (2) deterministic output buffering/sorting. The goals are to preserve streaming behavior, minimize memory churn, and keep deterministic output correct with bounded buffering.

---

## A. CBORStreamReader: Eliminate multi‑buffer merges, minimize copies

### Problem
`CBORStreamReader` currently merges multiple input buffers into a single `Data` via `DataBufferPair.combinedData()`. This creates large copies and defeats streaming for large inputs.

### Proposal
Introduce a segmented input cursor that reads across multiple `Data` segments without merging. Only copy when absolutely required (e.g., a string/bytes span crosses segment boundaries).

### Design
Create a local `CBORInputBuffer` type:
- Maintains a list of `Data` segments (`InlineArray<2, Data?>` + overflow if needed).
- Tracks `segmentIndex` and `segmentOffset`.
- `append(_ data: Data)` to add buffers.
- `availableBytes` (total bytes remaining across segments).
- `readByte() -> UInt8?` (advances cursor).
- `peekByte() -> UInt8?` (optional).
- `readBytes(count: Int) -> Data?`
  - Fast path: return a slice if fully contained in current segment (no copy).
  - Slow path: assemble across segments into a scratch `Data`.
- `consume(_ count: Int)` to drop consumed segments.

### Implementation steps
1. Replace `DataBufferPair` usage with `CBORInputBuffer` in `CBORStreamReader`.
2. Rewrite low‑level helper functions to use `CBORInputBuffer` instead of a monolithic `Data` + offset.
3. Update string/bytes decoding to only copy when necessary:
   - If contiguous, return a `Data` slice (or safe no‑copy view).
   - Otherwise, build a scratch `Data` and advance the cursor.
4. Add tests for multi‑segment boundary cases (varints, UTF‑8, bytes).

### Benefits
- Zero copies for most streaming reads.
- No full‑document buffering.
- Scales for huge inputs.

---

## B. Deterministic Output: Special buffering only where necessary

### Problem
Deterministic CBOR output requires sorting map keys by encoded bytes. Streaming must buffer to reorder keys; this is unavoidable. The current approach in `CBORValueWriter` works but is not optimized for streaming output.

### Proposal
Make deterministic output explicit and bounded in `CBORStreamWriter`, while keeping `CBORValueWriter` deterministic and optimized for common keys.

### B1. Deterministic mode for `CBORStreamWriter`
Add an explicit deterministic mode:

```
public enum DeterministicMode {
  case none
  case buffered(maxPairs: Int = 4096, maxBytes: Int = 8 * 1024 * 1024)
  case strict(maxPairs: Int = 4096, maxBytes: Int = 8 * 1024 * 1024)
}
```

- `.none`: always stream in input order.
- `.buffered`: buffer/sort maps only when feasible; fallback to non‑deterministic if limits exceeded or map is indefinite.
- `.strict`: throw if deterministic output can’t be guaranteed (indefinite map or buffer limits exceeded).

### B2. Map buffering algorithm (streaming writer)
When encoding `beginObject(count:)` with deterministic mode enabled:
- If `count == nil`:
  - `.buffered`: emit in input order (non‑deterministic).
  - `.strict`: throw.
- If `count` exceeds `maxPairs`:
  - `.buffered`: emit in input order.
  - `.strict`: throw.
- Otherwise, buffer `count` key/value pairs:
  1. For each pair, capture the key events and value events.
  2. Encode each pair to bytes using a temporary `CBOREncoder` + `CBORByteBuffer`.
  3. Store `(keyBytes, valueBytes)`.
  4. Sort pairs by `keyBytes` (length + lexicographic).
  5. Emit sorted pairs directly to the output sink.

### B3. Optimize deterministic sorting in `CBORValueWriter`
Add a fast sort‑key path for common key types:
- Strings and small integers: compute encoded bytes without full `CBOREncoder.encodeValue`.
- Fall back to full encode for complex keys.

This reduces per‑key allocations and CPU overhead.

### Benefits
- Streaming remains streaming for non‑deterministic mode.
- Deterministic mode is bounded and explicit.
- Value‑based writer stays deterministic and can be optimized for common keys.

---

## C. Optional: `assumeSortedKeys` fast path

For advanced callers:
- Add `assumeSortedKeys` deterministic mode.
- When enabled, writer skips buffering/sorting and assumes keys are already canonical.

---

## D. Implementation Plan (stepwise)

1. **Reader**: add `CBORInputBuffer`, remove `DataBufferPair`, update helpers, add boundary tests.
2. **Stream Writer**: implement deterministic mode + buffered map sorting with limits and strict/relaxed behavior.
3. **Value Writer**: optimize key sort keys for common types; keep full encode fallback.
4. **Tests**: add deterministic stream writer tests (buffered/strict + limit behavior) and multi‑buffer read tests.

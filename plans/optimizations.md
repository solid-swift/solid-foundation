# Optimization Backlog (Running Task List)

## Zero‑Copy Value Storage
- [ ] **BytesSlice and StringSlice support**
  - Define `Value.BytesSlice` and `Value.StringSlice` (or equivalent) to represent non‑contiguous buffers without copying.
  - Add bridging APIs to materialize into `Data`/`String` on demand.
  - Update decoders (CBOR/JSON/YAML) to emit slices where possible and only materialize for scalar conversions that require contiguous storage.
  - Audit Value equality/hash/ordering behavior with slices.

## CBOR Stream Reader
- [ ] Add zero‑copy `Data` slicing for contiguous reads using a stable backing store (avoid `subdata` copies).
- [ ] Extend `CBORInputBuffer` to surface non‑contiguous views for bytes/strings (to feed BytesSlice/StringSlice).
- [ ] Add streaming benchmarks for multi‑segment large strings/bytes.

## Deterministic CBOR Writing
- [ ] Implement pre‑sorted key fast path option (assume canonical ordering, skip buffering).
- [ ] Add configurable max buffering thresholds with metrics/logging to track fallback events.
- [ ] Optimize deterministic key ordering for complex key types (cached encoded bytes).

## ValueEvent Pipeline
- [ ] Allow passing raw byte slices through `ValueEvent` for bytes/string values to preserve zero‑copy parsing.
- [ ] Add lazy decoding hooks for `ValueEventDecoder` when slices are present.

## General Parsing/Encoding Performance
- [ ] Add per‑format microbenchmarks (small/large arrays, deep maps, large strings, mixed types).
- [ ] Profile allocator hot spots in stream parsing and encoding.
- [ ] Evaluate buffer sizes for `FormatStreamReaderDriver` and `FormatStreamWriterDriver`.

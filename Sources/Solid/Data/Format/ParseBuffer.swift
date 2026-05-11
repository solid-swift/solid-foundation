//
//  ParseBuffer.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 3/21/26.
//

import Foundation

/// A shared multi-segment input buffer for push parsers.
///
/// Supports incremental data appending, mark/restore for backtracking,
/// and zero-copy region references for lazy scalar materialization.
/// Uses inline storage for the first two segments to avoid heap allocation.
public struct ParseBuffer: ~Copyable, Sendable {

  /// A saved position within the buffer for backtracking.
  public struct Position: Sendable {
    let segmentIndex: Int
    let offset: Int
  }

  /// A zero-copy reference to a range of bytes within the buffer.
  ///
  /// Same-segment regions retain the full source `Data` segment. This keeps
  /// scalar events zero-copy and valid after compaction, but long-lived small
  /// regions can keep large input chunks alive. Use ``detached()`` when a
  /// caller needs to retain a small region independently of the parser input
  /// segment.
  public struct Region: Sendable {
    private enum Storage: Sendable {
      case retained(segment: Data, segmentIndex: Int?, segmentRange: Range<Int>)
      case copied(Data)
    }

    private let storage: Storage

    /// The raw bytes referenced by this region.
    ///
    /// Preserved for source compatibility and tests. New parser/resolver code
    /// should prefer ``bytes`` or ``withUnsafeBytes(_:)`` so `Region` remains
    /// the canonical retained-slice abstraction.
    public var data: Data { bytes }

    /// The raw bytes referenced by this region.
    public var bytes: Data {
      switch storage {
      case .retained(let segment, _, let segmentRange):
        return Self.copyBytes(from: segment, range: segmentRange)
      case .copied(let data):
        return data
      }
    }

    /// Number of bytes referenced by this region.
    public var count: Int {
      switch storage {
      case .retained(_, _, let segmentRange):
        return segmentRange.count
      case .copied(let data):
        return data.count
      }
    }

    /// Whether this region is empty.
    public var isEmpty: Bool { count == 0 }

    /// Number of bytes retained by this region's backing storage.
    public var retainedByteCount: Int {
      switch storage {
      case .retained(let segment, _, _):
        return segment.count
      case .copied(let data):
        return data.count
      }
    }

    /// Source segment index for contiguous regions retained from this buffer.
    public var segmentIndex: Int? {
      switch storage {
      case .retained(_, let segmentIndex, _):
        return segmentIndex
      case .copied:
        return nil
      }
    }

    /// Source byte range within `segmentIndex` for contiguous retained regions.
    public var segmentRange: Range<Int>? {
      switch storage {
      case .retained(_, let segmentIndex, let segmentRange):
        return segmentIndex == nil ? nil : segmentRange
      case .copied:
        return nil
      }
    }

    /// Whether this region had to be copied because it crossed segment boundaries.
    public var isCopied: Bool {
      if case .copied = storage { return true }
      return false
    }

    public init(data: Data) {
      self.storage = .retained(segment: data, segmentIndex: nil, segmentRange: 0 ..< data.count)
    }

    init(segment: Data, segmentIndex: Int?, segmentRange: Range<Int>) {
      self.storage = .retained(segment: segment, segmentIndex: segmentIndex, segmentRange: segmentRange)
    }

    init(copied data: Data) {
      self.storage = .copied(data)
    }

    /// Return a copied region that retains only this region's visible bytes.
    public func detached() -> Region {
      Region(copied: bytes)
    }

    /// Return a retained subregion when possible, falling back to a copied slice
    /// only when this region already owns copied storage.
    public func subregion(_ range: Range<Int>) -> Region {
      let lower = Swift.max(0, Swift.min(range.lowerBound, count))
      let upper = Swift.max(lower, Swift.min(range.upperBound, count))
      switch storage {
      case .retained(let segment, let segmentIndex, let segmentRange):
        return Region(
          segment: segment,
          segmentIndex: segmentIndex,
          segmentRange: (segmentRange.lowerBound + lower)..<(segmentRange.lowerBound + upper)
        )
      case .copied(let data):
        return Region(copied: Self.copyBytes(from: data, range: lower..<upper))
      }
    }

    /// Access this region's bytes without exposing the backing storage model.
    public func withUnsafeBytes<R>(
      _ body: (UnsafeRawBufferPointer) throws -> R
    ) rethrows -> R {
      switch storage {
      case .retained(let segment, _, let segmentRange):
        guard !segmentRange.isEmpty else {
          return try body(UnsafeRawBufferPointer(start: nil, count: 0))
        }
        return try segment.withUnsafeBytes { rawBuffer in
          guard let baseAddress = rawBuffer.baseAddress else {
            return try body(UnsafeRawBufferPointer(start: nil, count: 0))
          }
          return try body(
            UnsafeRawBufferPointer(
              start: baseAddress.advanced(by: segmentRange.lowerBound),
              count: segmentRange.count
            )
          )
        }
      case .copied(let data):
        return try data.withUnsafeBytes(body)
      }
    }

    /// Decode this region as UTF-8.
    public func string() throws -> String {
      try withUnsafeBytes { rawBuffer in
        guard !rawBuffer.isEmpty else { return "" }
        let utf8 = rawBuffer.bindMemory(to: UInt8.self)
        guard let string = String(bytes: utf8, encoding: .utf8) else {
          throw ParseBufferError.invalidUTF8
        }
        return string
      }
    }

    private static func copyBytes(from segment: Data, range: Range<Int>) -> Data {
      guard !range.isEmpty else { return Data() }
      return segment.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return Data() }
        var result = Data()
        result.reserveCapacity(range.count)
        result.append(baseAddress.advanced(by: range.lowerBound), count: range.count)
        return result
      }
    }
  }

  private var inline: InlineArray<2, Data?> = InlineArray(repeating: nil)
  private var overflow: ContiguousArray<Data> = []
  private var segmentBaseIndex: Int = 0
  private var segmentCount: Int = 0
  private var readIndex: Int = 0
  private var readOffset: Int = 0
  private var cursorInvalid: Bool = false

  public init() {}

  // MARK: - Input

  /// Whether the buffer has no unread bytes.
  public var isEmpty: Bool {
    mutating get {
      guard !cursorInvalid else { return true }
      var idx = readIndex
      var off = readOffset
      while idx < endSegmentIndex {
        guard let segment = segment(at: idx) else {
          idx += 1
          off = 0
          continue
        }
        if off < segment.count {
          return false
        }
        idx += 1
        off = 0
      }
      return true
    }
  }

  /// Append new input data to the buffer.
  public mutating func append(_ data: consuming Data) {
    guard !data.isEmpty else { return }
    let segment = data.startIndex == 0 && data.endIndex == data.count ? data : Data(data)
    if segmentCount < 2 {
      inline[segmentCount] = segment
    } else {
      overflow.append(segment)
    }
    segmentCount += 1
  }

  // MARK: - Reading

  /// Peek at the next byte without consuming it.
  public mutating func peekByte() -> UInt8? {
    guard let segment = ensureCurrentSegment() else { return nil }
    guard readOffset < segment.count else { return nil }
    return segment[readOffset]
  }

  /// Read and consume a single byte.
  public mutating func readByte() throws -> UInt8 {
    guard let segment = ensureCurrentSegment() else {
      throw ParseBufferError.unexpectedEnd
    }
    guard readOffset < segment.count else {
      throw ParseBufferError.unexpectedEnd
    }
    let byte = segment[readOffset]
    readOffset += 1
    return byte
  }

  /// Read and consume `count` bytes.
  public mutating func readBytes(count: Int) throws -> Data {
    guard count > 0 else { return Data() }
    guard hasAvailable(count) else { throw ParseBufferError.unexpectedEnd }

    guard let segment = ensureCurrentSegment() else {
      throw ParseBufferError.unexpectedEnd
    }

    // Fast path: all bytes in current segment
    if readOffset + count <= segment.count {
      let range = readOffset ..< (readOffset + count)
      readOffset += count
      return segment.subdata(in: range)
    }

    // Slow path: bytes span multiple segments
    var remaining = count
    var result = Data()
    result.reserveCapacity(count)

    while remaining > 0 {
      guard let current = ensureCurrentSegment() else {
        throw ParseBufferError.unexpectedEnd
      }
      let available = current.count - readOffset
      let take = min(available, remaining)
      let range = readOffset ..< (readOffset + take)
      Self.appendSlice(from: current, range: range, to: &result)
      readOffset += take
      remaining -= take
    }

    return result
  }

  /// Consume `count` bytes without materializing them.
  public mutating func advance(count: Int) throws {
    guard count > 0 else { return }
    guard advanceIfAvailable(count: count) else { throw ParseBufferError.unexpectedEnd }
  }

  /// Read and consume `count` bytes as a retained region when possible.
  public mutating func readRegion(count: Int) throws -> Region {
    guard count > 0 else { return Region(data: Data()) }
    let start = canonicalPosition(segmentIndex: readIndex, offset: readOffset)
    guard advanceIfAvailable(count: count) else { throw ParseBufferError.unexpectedEnd }
    return region(from: start, to: mark())
  }

  /// Read a fixed-width integer in big-endian byte order.
  public mutating func readInt<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
    let size = MemoryLayout<T>.size
    guard hasAvailable(size) else { throw ParseBufferError.unexpectedEnd }
    guard let segment = ensureCurrentSegment() else {
      throw ParseBufferError.unexpectedEnd
    }

    // Fast path: integer fits in current segment
    if readOffset + size <= segment.count {
      let value: T = segment.withUnsafeBytes { rawBuffer in
        rawBuffer.loadUnaligned(fromByteOffset: readOffset, as: T.self)
      }
      readOffset += size
      return T(bigEndian: value)
    }

    // Slow path: spans segments
    let bytes = try readBytes(count: size)
    let value: T = bytes.withUnsafeBytes { rawBuffer in
      rawBuffer.loadUnaligned(as: T.self)
    }
    return T(bigEndian: value)
  }

  // MARK: - Backtracking

  /// Save the current read position for later restoration.
  public func mark() -> Position {
    canonicalPosition(segmentIndex: readIndex, offset: readOffset)
  }

  /// Restore a previously saved read position.
  public mutating func restore(_ position: Position) {
    guard position.segmentIndex >= segmentBaseIndex else {
      cursorInvalid = true
      readIndex = position.segmentIndex
      readOffset = position.offset
      return
    }
    cursorInvalid = false
    readIndex = position.segmentIndex
    readOffset = position.offset
  }

  // MARK: - Regions

  /// Create a zero-copy `Region` from the bytes between two positions.
  ///
  /// The region keeps the underlying buffer segment(s) alive. For regions
  /// that span multiple segments, the data is copied into a contiguous buffer.
  public mutating func region(from start: Position, to end: Position) -> Region {
    guard
      start.segmentIndex >= segmentBaseIndex,
      end.segmentIndex >= segmentBaseIndex,
      start.segmentIndex <= end.segmentIndex,
      end.segmentIndex <= endSegmentIndex
    else {
      return Region(data: Data())
    }

    // Same segment — retain the parent segment and byte range.
    if start.segmentIndex == end.segmentIndex {
      guard let segment = segment(at: start.segmentIndex) else {
        return Region(data: Data())
      }
      let range = start.offset ..< end.offset
      return Region(
        segment: segment,
        segmentIndex: start.segmentIndex,
        segmentRange: range
      )
    }

    // Multi-segment — must copy
    var result = Data()
    var idx = start.segmentIndex
    var off = start.offset

    while idx <= end.segmentIndex {
      guard let seg = segment(at: idx) else {
        idx += 1
        off = 0
        continue
      }
      let endOff = (idx == end.segmentIndex) ? end.offset : seg.count
      if off < endOff {
        Self.appendSlice(from: seg, range: off ..< endOff, to: &result)
      }
      idx += 1
      off = 0
    }

    return Region(copied: result)
  }

  /// Resolve a retained region into bytes.
  public borrowing func bytes(for region: Region) -> Data {
    region.bytes
  }

  /// Access a retained region's bytes without requiring callers to materialize
  /// parser state. Contiguous regions keep the original segment alive; copied
  /// regions expose their contiguous copy.
  public borrowing func withUnsafeBytes<R>(
    for region: Region,
    _ body: (UnsafeRawBufferPointer) throws -> R
  ) rethrows -> R {
    try region.withUnsafeBytes(body)
  }

  /// Resolve a retained region into a UTF-8 string.
  public borrowing func string(for region: Region) throws -> String {
    try region.string()
  }

  // MARK: - Compaction

  /// Remove consumed segments to free memory.
  public mutating func compact() {
    guard !cursorInvalid else { return }
    _ = ensureCurrentSegment()
    guard readIndex > segmentBaseIndex else { return }

    var newInline: InlineArray<2, Data?> = InlineArray(repeating: nil)
    var newOverflow = ContiguousArray<Data>()
    var newCount = 0

    for idx in readIndex ..< endSegmentIndex {
      guard let seg = segment(at: idx) else { continue }
      if newCount < 2 {
        newInline[newCount] = seg
      } else {
        newOverflow.append(seg)
      }
      newCount += 1
    }

    inline = newInline
    overflow = newOverflow
    segmentBaseIndex = readIndex
    segmentCount = newCount
  }

  // MARK: - Private

  private func hasAvailable(_ count: Int) -> Bool {
    guard !cursorInvalid else { return false }
    var remaining = count
    var idx = readIndex
    var off = readOffset

    while remaining > 0 {
      guard let seg = segment(at: idx) else { return false }
      let available = seg.count - off
      if available >= remaining {
        return true
      }
      remaining -= available
      idx += 1
      off = 0
    }

    return true
  }

  private mutating func advanceIfAvailable(count: Int) -> Bool {
    guard !cursorInvalid else { return false }

    let start = canonicalPosition(segmentIndex: readIndex, offset: readOffset)
    var idx = start.segmentIndex
    var off = start.offset
    var remaining = count

    while remaining > 0 {
      guard let seg = segment(at: idx) else { return false }
      let available = seg.count - off
      if available >= remaining {
        readIndex = idx
        readOffset = off + remaining
        return true
      }
      remaining -= available
      idx += 1
      off = 0
    }

    readIndex = start.segmentIndex
    readOffset = start.offset
    return true
  }

  private func segment(at idx: Int) -> Data? {
    let localIndex = idx - segmentBaseIndex
    guard localIndex >= 0, localIndex < segmentCount else { return nil }
    if localIndex < 2 {
      return inline[localIndex]
    }
    let overflowIndex = localIndex - 2
    guard overflowIndex < overflow.count else { return nil }
    return overflow[overflowIndex]
  }

  private mutating func ensureCurrentSegment() -> Data? {
    guard !cursorInvalid else { return nil }
    guard readIndex >= segmentBaseIndex else {
      cursorInvalid = true
      return nil
    }

    while readIndex < endSegmentIndex {
      guard let seg = segment(at: readIndex) else {
        readIndex += 1
        readOffset = 0
        continue
      }
      if readOffset < seg.count {
        return seg
      }
      readIndex += 1
      readOffset = 0
    }
    return nil
  }

  private func canonicalPosition(segmentIndex: Int, offset: Int) -> Position {
    guard !cursorInvalid else {
      return Position(segmentIndex: segmentIndex, offset: offset)
    }

    guard segmentIndex < endSegmentIndex else {
      return Position(segmentIndex: endSegmentIndex, offset: 0)
    }

    var idx = segmentIndex
    var off = offset
    var exhaustedPosition: Position?
    while idx < endSegmentIndex {
      guard let segment = segment(at: idx) else {
        idx += 1
        off = 0
        continue
      }
      if off < segment.count {
        return Position(segmentIndex: idx, offset: off)
      }
      if exhaustedPosition == nil {
        exhaustedPosition = Position(segmentIndex: idx, offset: segment.count)
      }
      idx += 1
      off = 0
    }
    return exhaustedPosition ?? Position(segmentIndex: endSegmentIndex, offset: 0)
  }

  private var endSegmentIndex: Int {
    segmentBaseIndex + segmentCount
  }

  private static func appendSlice(from segment: Data, range: Range<Int>, to result: inout Data) {
    guard !range.isEmpty else { return }
    segment.withUnsafeBytes { rawBuffer in
      guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
      result.append(base.advanced(by: range.lowerBound), count: range.count)
    }
  }
}

/// Errors thrown by `ParseBuffer` when insufficient data is available.
public enum ParseBufferError: Error, Sendable {
  case unexpectedEnd
  case invalidUTF8
}

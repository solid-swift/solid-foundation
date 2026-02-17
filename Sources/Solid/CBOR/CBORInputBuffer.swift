//
//  CBORInputBuffer.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/17/26.
//

import Foundation

/// Multi-segment input buffer optimized for streaming CBOR parsing.
/// Uses inline storage for the first two segments to avoid heap allocation
/// in the common case, and supports zero-copy slicing via custom deallocators.
struct CBORInputBuffer {

  struct Position: Sendable {
    let index: Int
    let offset: Int
  }

  private var inline: InlineArray<2, Data?> = InlineArray(repeating: nil)
  private var overflow: [Data] = []
  private var count: Int = 0
  private var index: Int = 0
  private var offset: Int = 0

  var isEmpty: Bool {
    var idx = index
    var off = offset
    while idx < count {
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

  mutating func append(_ data: Data) {
    guard !data.isEmpty else { return }
    if count < 2 {
      inline[count] = data
    } else {
      overflow.append(data)
    }
    count += 1
  }

  func mark() -> Position {
    Position(index: index, offset: offset)
  }

  mutating func restore(_ position: Position) {
    index = position.index
    offset = position.offset
  }

  mutating func compactSegments() {
    _ = ensureCurrentSegment()
    guard index > 0 else { return }

    var newInline: InlineArray<2, Data?> = InlineArray(repeating: nil)
    var newOverflow: [Data] = []
    var newCount = 0

    for idx in index..<count {
      guard let segment = segment(at: idx) else { continue }
      if newCount < 2 {
        newInline[newCount] = segment
      } else {
        newOverflow.append(segment)
      }
      newCount += 1
    }

    inline = newInline
    overflow = newOverflow
    count = newCount
    index = 0
  }

  mutating func peekByte() -> UInt8? {
    guard let segment = ensureCurrentSegment() else { return nil }
    return segment[offset]
  }

  mutating func readByte() throws -> UInt8 {
    guard let segment = ensureCurrentSegment() else { throw CBOR.Error.unexpectedEndOfStream }
    let byte = segment[offset]
    offset += 1
    return byte
  }

  mutating func readBytes(count: Int) throws -> Data {
    guard count >= 0 else { return Data() }
    guard hasAvailable(count) else { throw CBOR.Error.unexpectedEndOfStream }
    guard count > 0 else { return Data() }

    guard let segment = ensureCurrentSegment() else { throw CBOR.Error.unexpectedEndOfStream }
    if offset + count <= segment.count {
      let range = offset..<(offset + count)
      offset += count
      return Self.makeNoCopySlice(from: segment, range: range)
    }

    var remaining = count
    var result = Data()
    result.reserveCapacity(count)

    while remaining > 0 {
      guard let current = ensureCurrentSegment() else { throw CBOR.Error.unexpectedEndOfStream }
      let available = current.count - offset
      let take = min(available, remaining)
      let range = offset..<(offset + take)
      result.append(current.subdata(in: range))
      offset += take
      remaining -= take
    }

    return result
  }

  mutating func readInt<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
    let size = MemoryLayout<T>.size
    guard hasAvailable(size) else { throw CBOR.Error.unexpectedEndOfStream }
    guard let segment = ensureCurrentSegment() else { throw CBOR.Error.unexpectedEndOfStream }

    if offset + size <= segment.count {
      let value: T = segment.withUnsafeBytes { rawBuffer in
        rawBuffer.loadUnaligned(fromByteOffset: offset, as: T.self)
      }
      offset += size
      return T(bigEndian: value)
    }

    let bytes = try readBytes(count: size)
    let value: T = bytes.withUnsafeBytes { rawBuffer in
      rawBuffer.loadUnaligned(as: T.self)
    }
    return T(bigEndian: value)
  }

  private func hasAvailable(_ count: Int) -> Bool {
    var remaining = count
    var idx = index
    var off = offset

    while remaining > 0 {
      guard let segment = segment(at: idx) else { return false }
      let available = segment.count - off
      if available >= remaining {
        return true
      }
      remaining -= available
      idx += 1
      off = 0
    }

    return true
  }

  private func segment(at idx: Int) -> Data? {
    guard idx < count else { return nil }
    if idx < 2 {
      return inline[idx]
    }
    let overflowIndex = idx - 2
    guard overflowIndex < overflow.count else { return nil }
    return overflow[overflowIndex]
  }

  private mutating func ensureCurrentSegment() -> Data? {
    while index < count {
      guard let segment = segment(at: index) else {
        index += 1
        offset = 0
        continue
      }
      if offset < segment.count {
        return segment
      }
      index += 1
      offset = 0
    }
    return nil
  }

  /// Zero-copy slice that keeps the parent segment alive via a custom deallocator,
  /// avoiding Data's copy-on-write overhead for sub-ranges.
  private static func makeNoCopySlice(from segment: Data, range: Range<Int>) -> Data {
    guard !range.isEmpty else { return Data() }
    return segment.withUnsafeBytes { rawBuffer in
      guard let base = rawBuffer.baseAddress else { return Data() }
      let pointer = base.advanced(by: range.lowerBound)
      return Data(
        bytesNoCopy: UnsafeMutableRawPointer(mutating: pointer),
        count: range.count,
        deallocator: .custom { _, _ in
          _ = segment
        }
      )
    }
  }
}

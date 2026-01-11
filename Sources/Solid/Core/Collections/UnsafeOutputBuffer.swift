//
//  UnsafeOutputBuffer.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/16/25.
//

import Algorithms
import Collections

/// A wrapper around `UnsafeMutableBufferPointer` that provides a mutable collection interface.
///
/// This struct manages a buffer of elements, allowing for dynamic resizing similar to a standard
/// Swift array up to the buffer's count.
///
/// Element access is bounds checked accoring the the current size of the array. If using one of the temporary
/// initlaizers that provides manages an uninitialized buffer
/// (e.g. ``Code/withUnsafeTemporaryBufferArray(repeating:count:_:)``) , you must use
/// ``UnsafeOutputBuffer/resize(to:)`` to enable access to the uninitialized elements.
///
@usableFromInline
package struct UnsafeOutputBuffer<Element> {

  public private(set) var buffer: UnsafeMutableBufferPointer<Element>
  public private(set) var initializedCount: Int

  public var capacity: Int { buffer.count }

  @usableFromInline
  package init(buffer: UnsafeMutableBufferPointer<Element>, initializedCount: Int) {
    precondition(buffer.count >= initializedCount, "Buffer count must be greater than or equal to count")
    self.buffer = buffer
    self.initializedCount = initializedCount
  }

  @usableFromInline
  package mutating func resize(to initializedCount: Int) {
    precondition(initializedCount <= buffer.count, "New count must be less than or equal to buffer capacity")
    self.initializedCount = initializedCount
  }

}

extension UnsafeOutputBuffer: RandomAccessCollection {

  public typealias Index = Int

  public var startIndex: Int { 0 }
  public var endIndex: Int { initializedCount }

  public subscript(position: Int) -> Element {
    get {
      assert(position >= 0 && position < count, "Index out of bounds")
      return buffer[position]
    }
    set {
      assert(position >= 0 && position < count, "Index out of bounds")
      buffer[position] = newValue
      initializedCount = Swift.max(count, position + 1)
    }
  }

}

extension UnsafeOutputBuffer: MutableCollection {}

extension UnsafeOutputBuffer: RangeReplaceableCollection {

  public init() {
    self.init(buffer: UnsafeMutableBufferPointer(start: nil, count: 0), initializedCount: 0)
  }

  public mutating func replaceSubrange<C>(_ subrange: Range<Int>, with newElements: C)
  where C: Collection, Element == C.Element {
    // Handle empty cases first
    guard !subrange.isEmpty || !newElements.isEmpty else { return }

    // Calculate new count after replacement
    let replacementCount = newElements.count
    let diff = replacementCount - subrange.count
    let newCount = count + diff
    precondition(newCount <= buffer.count, "New elements would exceed buffer capacity")

    // Shift remaining elements left or right
    let remaining = UnsafeMutableBufferPointer(rebasing: buffer[subrange.upperBound..<count])
    let remainingTarget = UnsafeMutableBufferPointer(rebasing: buffer[subrange.upperBound + diff..<count + diff])
    remainingTarget.baseAddress.unsafelyUnwrapped.initialize(
      from: remaining.baseAddress.unsafelyUnwrapped,
      count: remaining.count
    )

    // Copy new elements into place
    let newTarget =
      UnsafeMutableBufferPointer(rebasing: buffer[subrange.lowerBound..<subrange.lowerBound + replacementCount])
    let initNewCount = newTarget.initialize(fromContentsOf: newElements)
    assert(initNewCount == newElements.count)

    // Update count
    initializedCount = Swift.max(initializedCount, newCount)
  }

}

@inline(__always)
package func withUnsafeOutputBuffer<Element, R>(
  repeating: Element,
  count: Int,
  _ body: (inout UnsafeOutputBuffer<Element>) throws -> R
) rethrows -> R {
  try withUnsafeTemporaryAllocation(of: Element.self, capacity: count) { buffer in
    buffer.initialize(repeating: repeating)
    var array = UnsafeOutputBuffer(buffer: buffer, initializedCount: 0)
    return try body(&array)
  }
}

@inline(__always)
package func withUnsafeOutputBuffer<Element, R>(
  from source: some Collection<Element>,
  additional: (repeating: Element, count: Int)? = nil,
  _ body: (inout UnsafeOutputBuffer<Element>) throws -> R
) rethrows -> R {
  try withUnsafeTemporaryAllocation(of: Element.self, capacity: source.count + (additional?.count ?? 0)) { buffer in
    if let (additionalElement, additionalCount) = additional {
      let unitializedIndex = buffer.initialize(fromContentsOf: source)
      _ = buffer[unitializedIndex...]
        .initialize(fromContentsOf: repeatElement(additionalElement, count: additionalCount))
    } else {
      let initialized = buffer.initialize(fromContentsOf: source)
      assert(initialized == source.count)
    }
    var array = UnsafeOutputBuffer(buffer: buffer, initializedCount: source.count)
    return try body(&array)
  }
}

@inline(__always)
package func withUnsafeOutputBuffer<Element, R>(
  of: Element.Type = Element.self,
  count: Int,
  _ body: (inout UnsafeOutputBuffer<Element>) -> R
) -> R {
  return withUnsafeTemporaryAllocation(of: Element.self, capacity: count) { wordBuffer in
    var array = wordBuffer.output(to: 0..<count)
    return body(&array)
  }
}

@inline(__always)
package func withUnsafeOutputBuffers<Element, R>(
  counts: (Int, Int),
  body: (inout UnsafeOutputBuffer<Element>, inout UnsafeOutputBuffer<Element>) -> R
) -> R {
  return withUnsafeTemporaryAllocation(of: Element.self, capacity: counts.0 + counts.1) { wordBuffer in
    var a = wordBuffer.output(to: 0..<counts.0)
    var b = wordBuffer.output(to: counts.0..<(counts.0 + counts.1))
    return body(&a, &b)
  }
}

package extension UnsafeMutableBufferPointer {

  @inlinable
  func output(to range: Range<Index>, initializedCount: Int = 0) -> UnsafeOutputBuffer<Element> {
    return UnsafeOutputBuffer(buffer: extracting(range), initializedCount: initializedCount)
  }

}

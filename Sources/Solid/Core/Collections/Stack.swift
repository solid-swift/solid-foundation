//
//  Stack.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 6/26/24.
//

/// A last-in, first-out collection.
///
/// A stack presents its top element at `startIndex`. Initial elements and
/// elements pushed as a sequence retain their input order when read or popped.
///
public struct Stack<Element>: BidirectionalCollection {

  /// The storage type used by the stack.
  public typealias Storage = [Element]

  /// An index into the stack.
  public typealias Index = Storage.Index

  /// The stack's top-first iterator.
  public typealias Iterator = ReversedCollection<Storage>.Iterator

  /// A contiguous top-first slice of the stack.
  public typealias SubSequence = Slice<Self>

  private var storage: Storage

  /// Creates a stack whose top-to-bottom order matches `elements`.
  ///
  /// - Parameter elements: Elements ordered from the top to the bottom of the stack.
  public init(_ elements: Storage = []) {
    self.storage = elements.reversed()
  }

  /// Whether the stack contains no elements.
  public var isEmpty: Bool { storage.isEmpty }

  /// The number of elements in the stack.
  public var depth: Int { storage.count }

  /// Returns the top element without removing it.
  public func peek() -> Element? {
    storage.last
  }

  /// Adds an element to the top of the stack.
  public mutating func push(_ element: Element) {
    storage.append(element)
  }

  /// Adds elements so their top-to-bottom order matches `elements`.
  public mutating func push(contentsOf elements: some Sequence<Element>) {
    storage.append(contentsOf: elements.reversed())
  }

  /// Removes and returns the top element.
  ///
  /// - Precondition: The stack is not empty.
  public mutating func pop() -> Element {
    storage.removeLast()
  }

  /// Removes and returns the requested number of top elements.
  ///
  /// - Parameter count: Number of elements to remove.
  /// - Returns: Removed elements in top-to-bottom order.
  /// - Precondition: `count` is nonnegative and does not exceed ``depth``.
  public mutating func pop(_ count: Int = 1) -> [Element] {
    precondition(count >= 0 && count <= storage.count, "Stack underflow")
    let result = Array(storage.suffix(count))
    storage.removeLast(count)
    return Array(result.reversed())
  }

  /// Removes all elements from the stack.
  public mutating func popAll() {
    storage.removeAll()
  }

  /// The position of the stack's top element.
  public var startIndex: Index { storage.startIndex }

  /// The position immediately after the stack's bottom element.
  public var endIndex: Index { storage.endIndex }

  /// Returns the position immediately after `index`.
  public func index(after index: Index) -> Index {
    storage.index(after: index)
  }

  /// Returns the position immediately before `index`.
  public func index(before index: Index) -> Index {
    storage.index(before: index)
  }

  /// Returns the position offset from `index` by `distance`.
  public func index(_ index: Index, offsetBy distance: Int) -> Index {
    storage.index(index, offsetBy: distance)
  }

  /// Accesses the element at `position`, counting from the top of the stack.
  public subscript(position: Index) -> Element {
    storage[depth - 1 - position]
  }

  /// Returns an iterator over the stack in top-to-bottom order.
  public func makeIterator() -> Iterator {
    storage.reversed().makeIterator()
  }
}

extension Stack: Sendable where Element: Sendable {}

extension Stack: ExpressibleByArrayLiteral {

  /// Creates a stack whose top-to-bottom order matches `elements`.
  public init(arrayLiteral elements: Element...) {
    self.init(elements)
  }
}

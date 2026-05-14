//
//  ContainerStack.swift
//  SolidFoundation
//
//  Created by Codex on 4/24/26.
//

/// Shared parser-side nesting tracker for event streams that use implicit
/// object key/value alternation.
package struct ContainerStack: Sendable {

  private static let defaultInitialCapacity = 8

  package enum Frame: Sendable, Equatable {
    case array(remaining: Int?)
    case object(remaining: Int?, expectingKey: Bool)

    package var isIndefinite: Bool {
      switch self {
      case .array(let remaining), .object(let remaining, _):
        return remaining == nil
      }
    }
  }

  private var frames: ContiguousArray<Frame> = []
  private var shouldReserveDefaultOnFirstPush = true

  package init() {}

  package init(reservingCapacity capacity: Int) {
    shouldReserveDefaultOnFirstPush = false
    if capacity > 0 {
      frames.reserveCapacity(capacity)
    }
  }

  package var isEmpty: Bool { frames.isEmpty }
  package var count: Int { frames.count }
  package var current: Frame? { frames.last }

  package var isExpectingObjectKey: Bool {
    guard case .object(_, true) = frames.last else { return false }
    return true
  }

  package var isExpectingObjectValue: Bool {
    guard case .object(_, false) = frames.last else { return false }
    return true
  }

  package mutating func pushArray(count: Int?) {
    reserveForFirstPushIfNeeded()
    frames.append(.array(remaining: count))
  }

  package mutating func pushObject(count: Int?) {
    reserveForFirstPushIfNeeded()
    frames.append(.object(remaining: count, expectingKey: true))
  }

  @discardableResult
  package mutating func pop() throws -> Frame {
    guard let frame = frames.popLast() else {
      throw ContainerStackError.unbalancedEnd
    }
    return frame
  }

  /// Records completion of a scalar value in the current container.
  package mutating func didFinishScalarValue() {
    didFinishValue()
  }

  /// Records completion of a nested container value in the parent container.
  package mutating func didFinishContainerValue() {
    didFinishValue()
  }

  /// Whether the top definite-length container is complete and should emit its
  /// corresponding end event before reading more input.
  package var completedDefiniteContainer: Frame? {
    guard let frame = frames.last else { return nil }
    switch frame {
    case .array(let remaining):
      return remaining == 0 ? frame : nil
    case .object(let remaining, let expectingKey):
      return remaining == 0 && expectingKey ? frame : nil
    }
  }

  /// Whether an indefinite container can legally consume a break byte now.
  package var canConsumeBreak: Bool {
    guard let frame = frames.last, frame.isIndefinite else { return false }
    if case .object(_, let expectingKey) = frame {
      return expectingKey
    }
    return true
  }

  /// Whether a value at the current position is semantically legal.
  ///
  /// This validates definite-length container capacity and object key/value
  /// alternation. At the root, only non-key values are accepted.
  package func canAcceptValue(isKey: Bool) -> Bool {
    guard let frame = frames.last else {
      return !isKey
    }
    switch frame {
    case .array(let remaining):
      return !isKey && remaining != 0
    case .object(let remaining, let expectingKey):
      guard remaining != 0 else { return false }
      return isKey == expectingKey
    }
  }

  package func validateCanAcceptValue(isKey: Bool) throws {
    guard canAcceptValue(isKey: isKey) else {
      throw ContainerStackError.invalidValuePosition
    }
  }

  private mutating func reserveForFirstPushIfNeeded() {
    if frames.isEmpty && shouldReserveDefaultOnFirstPush {
      frames.reserveCapacity(Self.defaultInitialCapacity)
      shouldReserveDefaultOnFirstPush = false
    }
  }

  private mutating func didFinishValue() {
    guard !frames.isEmpty else { return }
    let idx = frames.count - 1

    switch frames[idx] {
    case .array(let remaining):
      if let remaining {
        frames[idx] = .array(remaining: remaining - 1)
      }

    case .object(let remaining, let expectingKey):
      if expectingKey {
        frames[idx] = .object(remaining: remaining, expectingKey: false)
      } else if let remaining {
        frames[idx] = .object(remaining: remaining - 1, expectingKey: true)
      } else {
        frames[idx] = .object(remaining: nil, expectingKey: true)
      }
    }
  }
}

package enum ContainerStackError: Error, Sendable {
  case unbalancedEnd
  case invalidValuePosition
}

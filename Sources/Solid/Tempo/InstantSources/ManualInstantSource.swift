//
//  ManualInstantSource.swift
//  SolidFoundation
//

import Synchronization

/// A manually advanced monotonic instant source.
///
/// This source is useful for deterministic tests and simulations.
public final class ManualInstantSource: MonotonicInstantSource, Sendable {

  /// Errors produced while advancing a manual source.
  public enum AdvanceError: Swift.Error, Equatable {
    /// The supplied duration was negative and would violate monotonicity.
    case negativeDuration
  }

  private let lockedInstant: Mutex<Instant>

  /// The current manually controlled instant.
  public var instant: Instant { lockedInstant.withLock { $0 } }

  /// Creates a manual source at `instant`.
  public init(instant: Instant = .epoch) {
    self.lockedInstant = Mutex(instant)
  }

  /// Advances this source by a nonnegative duration.
  public func advance(by duration: Duration) throws(AdvanceError) {
    guard duration >= .zero else { throw .negativeDuration }
    lockedInstant.withLock { $0 += duration }
  }
}


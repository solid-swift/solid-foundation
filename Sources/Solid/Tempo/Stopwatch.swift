//
//  Stopwatch.swift
//  SolidFoundation
//

import Synchronization

/// A thread-safe accumulator for elapsed monotonic time.
public final class Stopwatch: Sendable {

  private struct State: Sendable {
    var elapsed = Duration.zero
    var startedAt: Instant?
  }

  /// The monotonic source sampled by this stopwatch.
  public let source: any MonotonicInstantSource

  private let state = Mutex(State())

  /// Creates a stopped stopwatch using `source`.
  public init(source: any MonotonicInstantSource = UptimeInstantSource.instance) {
    self.source = source
  }

  /// The accumulated elapsed duration, including the current running interval.
  public var elapsed: Duration {
    state.withLock { state in
      guard let startedAt = state.startedAt else { return state.elapsed }
      return state.elapsed + elapsedSince(startedAt)
    }
  }

  /// Whether the stopwatch is currently running.
  public var isRunning: Bool { state.withLock { $0.startedAt != nil } }

  /// Starts or resumes the stopwatch.
  ///
  /// Calling this method while the stopwatch is running has no effect.
  public func start() {
    state.withLock { state in
      guard state.startedAt == nil else { return }
      state.startedAt = source.instant
    }
  }

  /// Stops the stopwatch and retains its accumulated duration.
  ///
  /// Calling this method while the stopwatch is stopped has no effect.
  public func stop() {
    state.withLock { state in
      guard let startedAt = state.startedAt else { return }
      state.elapsed += elapsedSince(startedAt)
      state.startedAt = nil
    }
  }

  /// Stops the stopwatch and clears its accumulated duration.
  public func reset() {
    state.withLock { $0 = State() }
  }

  /// Clears the accumulated duration and starts the stopwatch.
  public func restart() {
    state.withLock { state in
      state.elapsed = .zero
      state.startedAt = source.instant
    }
  }

  private func elapsedSince(_ start: Instant) -> Duration {
    let current = source.instant
    precondition(current >= start, "Monotonic instant source moved backward")
    return current - start
  }
}

//
//  ReadersWriterLock.swift
//  SolidFoundation
//
//  High-performance reader/writer lock for synchronizing access to mostly-read, rarely-written data.
//  Uses POSIX pthread_rwlock for scalability with multiple concurrent readers.
//
//  Created by Warp Agent on 12/25/2025.
//

#if canImport(Darwin)
  import Darwin
#else
  import Glibc
#endif


/// A high-performance reader/writer lock suitable for protecting fairly-constant data structures.
///
/// - Multiple readers may hold the lock concurrently.
/// - Writers acquire exclusive access.
/// - Provides convenient closure-based APIs as well as RAII guard helpers.
///
/// Notes
/// - This implementation is built on `pthread_rwlock_t` for portability and good read scalability.
/// - It intentionally avoids recursive locking semantics; attempting to re-acquire from the same thread
///   while already holding a lock leads to undefined behavior, matching pthread semantics.
public final class ReadersWriterLock: @unchecked Sendable {

  private var rwlock = pthread_rwlock_t()

  // MARK: - Init/Deinit

  public init() {
    var attr = pthread_rwlockattr_t()
    pthread_rwlockattr_init(&attr)
    // Default attributes generally perform well. Some platforms provide reader-preference attrs
    // (e.g., PTHREAD_RWLOCK_PREFER_READER_NP) but those are non-portable, so we stick to defaults.
    pthread_rwlock_init(&rwlock, &attr)
    pthread_rwlockattr_destroy(&attr)
  }

  deinit {
    pthread_rwlock_destroy(&rwlock)
  }

  // MARK: - Raw operations

  /// Acquire the lock for reading, blocking until acquired.
  ///
  public func lockRead() {
    pthread_rwlock_rdlock(&rwlock)
  }

  /// Try to acquire the lock for reading without blocking.
  ///
  /// - Returns: `true` if the lock was acquired..
  ///
  @discardableResult
  public func tryLockRead() -> Bool {
    pthread_rwlock_tryrdlock(&rwlock) == 0
  }

  /// Acquire the lock for writing, blocking until acquired.
  ///
  public func lockWrite() {
    pthread_rwlock_wrlock(&rwlock)
  }

  /// Try to acquire the lock for writing.
  ///
  /// - Returns: `true` if the lock was acquired..
  ///
  @discardableResult
  public func tryLockWrite() -> Bool {
    pthread_rwlock_trywrlock(&rwlock) == 0
  }

  /// Unlock from either a read or write state.
  ///
  public func unlock() {
    pthread_rwlock_unlock(&rwlock)
  }

  // MARK: - Closure helpers

  /// Execute `body` while holding a shared (read) lock.
  ///
  public func withReadLock<R>(_ body: () throws -> R) rethrows -> R {
    lockRead()
    defer { unlock() }
    return try body()
  }

  /// Execute `body` while holding an exclusive (write) lock.
  ///
  public func withWriteLock<R>(_ body: () throws -> R) rethrows -> R {
    lockWrite()
    defer { unlock() }
    return try body()
  }

  /// Attempt to execute `body` under a shared (read) lock.
  ///
  /// - Returns: The result of `body` or `nil` if the lock couldn't be acquired immediately.
  ///
  public func tryWithReadLock<R>(_ body: () throws -> R) rethrows -> R? {
    guard tryLockRead() else { return nil }
    defer { unlock() }
    return try body()
  }

  /// Attempt to execute `body` under an exclusive (write) lock.
  ///
  /// - Returns: The result of `body` or `nil` if the lock couldn't be acquired immediately.
  ///
  public func tryWithWriteLock<R>(_ body: () throws -> R) rethrows -> R? {
    guard tryLockWrite() else { return nil }
    defer { unlock() }
    return try body()
  }
}

// MARK: - RAII Guards
extension ReadersWriterLock {

  /// A scope guard that holds a read lock for the lifetime of the value.
  ///
  public struct ReadGuard: ~Copyable {
    @usableFromInline let lock: ReadersWriterLock
    init(_ lock: ReadersWriterLock) { self.lock = lock }
    deinit { lock.unlock() }
  }

  /// A scope guard that holds a write lock for the lifetime of the value.
  ///
  public struct WriteGuard: ~Copyable {
    @usableFromInline let lock: ReadersWriterLock
    @inlinable init(_ lock: ReadersWriterLock) { self.lock = lock }
    @inlinable deinit { lock.unlock() }
  }

  /// Acquire a read guard, blocking until the lock is acquired.
  ///
  public func readLocked() -> ReadGuard {
    lockRead()
    return ReadGuard(self)
  }

  /// Try to acquire a read guard without blocking.
  ///
  public func tryReadLocked() -> ReadGuard? {
    tryLockRead() ? ReadGuard(self) : nil
  }

  /// Acquire a write guard, blocking until the lock is acquired.
  ///
  public func writeLocked() -> WriteGuard {
    lockWrite()
    return WriteGuard(self)
  }

  /// Try to acquire a write guard without blocking.
  ///
  public func tryWriteLocked() -> WriteGuard? {
    tryLockWrite() ? WriteGuard(self) : nil
  }
}

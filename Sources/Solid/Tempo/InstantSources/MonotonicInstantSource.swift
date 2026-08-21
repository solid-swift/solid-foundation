//
//  MonotonicInstantSource.swift
//  SolidFoundation
//

/// A source whose instants never decrease.
///
/// Monotonic sources are suitable for measuring elapsed time. Their epoch is
/// source-specific and must not be interpreted as calendar time unless the
/// concrete source documents that behavior.
public protocol MonotonicInstantSource: InstantSource {}

//
//  UptimeInstantSource.swift
//  SolidFoundation
//

/// A monotonic source measuring time while the system is awake.
///
/// The source-specific epoch is arbitrary and is not suitable for calendar conversion.
public struct UptimeInstantSource: MonotonicInstantSource {

  /// The shared uptime source.
  public static let instance = Self()

  private init() {}

  // Implementation based on platform-specific APIs.
  // Darwin: UptimeInstantSource+Darwin.swift
  // Linux: UptimeInstantSource+Linux.swift
}
extension MonotonicInstantSource where Self == UptimeInstantSource {

  /// The system uptime source.
  public static var uptime: Self { .instance }
}

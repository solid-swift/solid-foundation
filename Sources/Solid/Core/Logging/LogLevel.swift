//
//  LogLevel.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/28/25.
//

import Synchronization


public enum LogLevel: Int, Equatable, Hashable, Comparable, Sendable {

  case trace = 0
  case debug = 1
  case info = 2
  case notice = 3
  case warning = 4
  case error = 5
  case critical = 6

  public var name: String {
    switch self {
    case .trace:
      return "trace"
    case .debug:
      return "debug"
    case .info:
      return "info"
    case .notice:
      return "notice"
    case .warning:
      return "warning"
    case .error:
      return "error"
    case .critical:
      return "critical"
    }
  }

  public static func value(forName name: String) -> Self? {
    switch name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
    case Self.trace.name, "0": .trace
    case Self.debug.name, "1": .debug
    case Self.info.name, "2": .info
    case Self.notice.name, "3": .notice
    case Self.warning.name, "4": .warning
    case Self.error.name, "5": .error
    case Self.critical.name, "6": .critical
    default: nil
    }
  }

  @inlinable
  public func isEnabled(in minimumLevel: Self) -> Bool {
    return self >= minimumLevel
  }

  @inlinable
  public static func < (lhs: Self, rhs: Self) -> Bool {
    return lhs.rawValue < rhs.rawValue
  }

}

extension LogLevel: AtomicRepresentable {}


extension LogLevel: EnvironmentVariableDiscoverable {

  public static let environmentVariableNames = ["SOLID_LOG_LEVEL"]
  public static var environmentDefaultValue: LogLevel? {
    switch RuntimeEnvironment.selected {
    case .development, .testing:
      return .debug
    default:
      return .info
    }
  }

  public init?(environmentVariableValue: String) {
    guard let value = LogLevel.value(forName: environmentVariableValue.lowercased()) else {
      return nil
    }
    self = value
  }
}

private let defaultLevelStorage = Atomic<LogLevel>(
  ProcessEnvironment.instance.value(for: LogLevel.self) ?? .info
)

extension LogLevel {

  public static var `default`: LogLevel {
    get { defaultLevelStorage.load(ordering: .acquiring) }
    set { defaultLevelStorage.store(newValue, ordering: .releasing) }
  }

}

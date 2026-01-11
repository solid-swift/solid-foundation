//
//  LogPrivacy.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/28/25.
//

import Crypto
import Foundation
import Synchronization


public enum LogPrivacy: Int, Hashable, Sendable {
  case `public`
  case sensitive
  case `private`

  public var name: String {
    switch self {
    case .public:
      return "public"
    case .sensitive:
      return "sensitive"
    case .private:
      return "private"
    }
  }

  public static func value(forName name: String) -> Self? {
    switch name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
    case Self.public.name: .public
    case Self.sensitive.name: .sensitive
    case Self.private.name: .private
    default: nil
    }
  }
}

extension LogPrivacy {

  private func redact(_ value: String) -> String {
    "[\(String(repeating: "*", count: value.count))]"
  }

  private func obscure(_ value: String) -> String {
    let inputData = Data(value.utf8)
    let hashed = SHA256.hash(data: inputData)
    return hashed.prefix(8).map { String(format: "%02x", $0) }.joined()
  }

  public func redact(_ argument: some LogArgument, for allowed: LogPrivacy) -> String {
    switch allowed {
    case .public:
      switch self {
      case .public:
        return argument.formattedValue
      case .sensitive, .private:
        return redact(argument.constantValue)
      }
    case .sensitive:
      switch self {
      case .public:
        return argument.formattedValue
      case .sensitive:
        return obscure(argument.constantValue)
      case .private:
        return redact(argument.constantValue)
      }
    case .private:
      return argument.formattedValue
    }
  }

}


extension LogPrivacy: AtomicRepresentable {}


extension LogPrivacy: EnvironmentVariableDiscoverable {

  public static let environmentVariableNames = ["SOLID_LOG_PRIVACY"]
  public static var environmentDefaultValue: LogPrivacy? {
    switch RuntimeEnvironment.selected {
    case .development, .testing:
      return .sensitive
    case .staging:
      return .private
    default:
      return .public
    }
  }

  public init?(environmentVariableValue: String) {
    guard let value = LogPrivacy.value(forName: environmentVariableValue.lowercased()) else {
      return nil
    }
    self = value
  }
}

private let defaultPrivacyStorage = Atomic<LogPrivacy>(
  ProcessEnvironment.instance.value(for: LogPrivacy.self) ?? .private
)

extension LogPrivacy {

  public static var `default`: LogPrivacy {
    get { defaultPrivacyStorage.load(ordering: .acquiring) }
    set { defaultPrivacyStorage.store(newValue, ordering: .releasing) }
  }

}

//
//  SwiftLogIntegration.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/28/25.
//

#if canImport(Logging)

  import Logging
  import Synchronization

  public extension LogFactory {

    static func `for`(category: String, name: String, level: LogLevel, privacy: LogPrivacy) -> SwiftLogLog {
      .init(label: "\(category).\(name)", level: level, privacy: privacy)
    }

  }

  extension LogLevel {

    init(swiftLog: Logger.Level) {
      self =
        switch swiftLog {
        case .trace: .trace
        case .debug: .debug
        case .info: .info
        case .notice: .notice
        case .warning: .warning
        case .error: .error
        case .critical: .critical
        }
    }

    var swiftLog: Logger.Level {
      switch self {
      case .trace: .trace
      case .debug: .debug
      case .info: .info
      case .notice: .notice
      case .warning: .warning
      case .error: .error
      case .critical: .critical
      }
    }

  }


  public struct SwiftLogLog: Log {

    public var destination: Logger
    public var privacy: LogPrivacy
    public var level: LogLevel { .init(swiftLog: destination.logLevel) }

    public init(label: String, level: LogLevel, privacy: LogPrivacy) {
      self.destination = Logger(label: label)
      self.destination.logLevel = level.swiftLog
      self.privacy = privacy
    }

    public func log(_ event: LogEvent) {
      guard isEnabled(for: event.level) else {
        return
      }
      let message = Logger.Message(stringLiteral: event.message.formattedString(for: privacy))
      let level: Logger.Level =
        switch event.level {
        case .trace: .trace
        case .debug: .debug
        case .info: .info
        case .notice: .notice
        case .warning: .warning
        case .error: .error
        case .critical: .critical
        }
      destination.log(level: level, message)
    }

  }

#endif

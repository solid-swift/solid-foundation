//
//  OSLogIntegration.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/28/25.
//

#if !canImport(Logging)

  import OSLog
  import Synchronization


  public extension LogFactory {

    static func `for`(category: String, name: String) -> OSLogLog {
      let logger = Logger(subsystem: category, category: name)
      return OSLogLog(destination: logger)
    }

  }


  public struct OSLogLog: Log {

    public let level = LogLevel.trace
    public let privacy = LogPrivacy.private
    public let destination: Logger

    public init(destination: Logger) {
      self.destination = destination
    }

    public func log(_ event: LogEvent) {
      let formattedMessage = event.message.formattedString(for: self.privacy)
      switch event.level {
      case .trace:
        destination.trace("\(formattedMessage, privacy: .public)")
      case .debug:
        destination.debug("\(formattedMessage, privacy: .public)")
      case .info:
        destination.info("\(formattedMessage, privacy: .public)")
      case .notice:
        destination.notice("\(formattedMessage, privacy: .public)")
      case .warning:
        destination.warning("\(formattedMessage, privacy: .public)")
      case .error:
        destination.error("\(formattedMessage, privacy: .public)")
      case .critical:
        destination.critical("\(formattedMessage, privacy: .public)")
      }
    }

  }

#endif

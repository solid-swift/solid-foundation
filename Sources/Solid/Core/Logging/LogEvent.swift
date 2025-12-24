//
//  LogEvent.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/28/25.
//


public struct LogEvent: Sendable {

  public var level: LogLevel
  public var message: LogMessage
  public var context: LogContext = [:]
  public var location: LogSourceLocation

  @inlinable
  public init(level: LogLevel, message: LogMessage, context: LogContext, location: LogSourceLocation) {
    self.level = level
    self.message = message
    self.context = context
    self.location = location
  }

  @inlinable
  public init(
    level: LogLevel,
    message: LogMessage,
    context: LogContext,
    function: StaticString,
    file: StaticString,
    line: UInt
  ) {
    self.level = level
    self.message = message
    self.context = context
    self.location = .init(function: LogStaticString(function), file: LogStaticString(file), line: line)
  }

}

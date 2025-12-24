//
//  Log.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/28/25.
//


public protocol Log: Sendable {

  var level: LogLevel { get }

  func isEnabled(for level: LogLevel) -> Bool

  func log(_ event: LogEvent)

}


public extension Log {

  @inlinable
  func isEnabled(for level: LogLevel) -> Bool {
    return level.isEnabled(in: self.level)
  }

  @inlinable
  func ifEnabled(
    _ level: LogLevel,
    perform block: () throws -> Void
  ) {
    guard isEnabled(for: level) else {
      return
    }
    do {
      return try block()
    } catch {
      critical("Conditional log evaluation failed: \(error)")
    }
  }

  @inlinable func ifTrace(perform block: () throws -> Void) { ifEnabled(.debug, perform: block) }
  @inlinable func ifDebug(perform block: () throws -> Void) { ifEnabled(.debug, perform: block) }
  @inlinable func ifInfo(perform block: () throws -> Void) { ifEnabled(.info, perform: block) }
  @inlinable func ifNotice(perform block: () throws -> Void) { ifEnabled(.notice, perform: block) }
  @inlinable func ifWarning(perform block: () throws -> Void) { ifEnabled(.warning, perform: block) }
  @inlinable func ifError(perform block: () throws -> Void) { ifEnabled(.error, perform: block) }
  @inlinable func ifCritical(perform block: () throws -> Void) { ifEnabled(.critical, perform: block) }

  @inlinable
  func log(
    _ level: LogLevel,
    message: LogMessage,
    context: LogContext,
    function: StaticString = #function,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    log(.init(level: level, message: message, context: context, function: function, file: file, line: line))
  }

  @inlinable
  func log(
    _ level: LogLevel,
    message: LogMessage,
    localContext: [String: any Sendable] = [:],
    function: StaticString = #function,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    let scope = FunctionLogScope(function: function, file: file)
    let context = localContext.map { (LogContextKey(scope: scope, key: $0.key), $0.value) }.associated()
    log(.init(level: level, message: message, context: context, function: function, file: file, line: line))
  }

  @inlinable
  func trace(
    _ message: LogMessage,
    _ localContext: [String: any Sendable] = [:],
    function: StaticString = #function,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    log(.trace, message: message, localContext: localContext, function: function, file: file, line: line)
  }

  @inlinable
  func debug(
    _ message: LogMessage,
    _ localContext: [String: any Sendable] = [:],
    function: StaticString = #function,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    log(.debug, message: message, localContext: localContext, function: function, file: file, line: line)
  }

  @inlinable
  func info(
    _ message: LogMessage,
    _ localContext: [String: any Sendable] = [:],
    function: StaticString = #function,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    log(.info, message: message, function: function, file: file, line: line)
  }

  @inlinable
  func notice(
    _ message: LogMessage,
    _ localContext: [String: any Sendable] = [:],
    function: StaticString = #function,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    log(.notice, message: message, function: function, file: file, line: line)
  }

  @inlinable
  func warning(
    _ message: LogMessage,
    _ localContext: [String: any Sendable] = [:],
    function: StaticString = #function,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    log(.warning, message: message, function: function, file: file, line: line)
  }

  @inlinable
  func error(
    _ message: LogMessage,
    _ localContext: [String: any Sendable] = [:],
    function: StaticString = #function,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    log(.error, message: message, function: function, file: file, line: line)
  }

  @inlinable
  func critical(
    _ message: LogMessage,
    _ localContext: [String: any Sendable] = [:],
    function: StaticString = #function,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    log(.critical, message: message, function: function, file: file, line: line)
  }

}

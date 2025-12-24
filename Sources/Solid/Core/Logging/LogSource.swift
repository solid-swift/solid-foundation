//
//  LogSource.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/28/25.
//


public typealias LogSourceFunction = LogStaticString
public typealias LogSourceFile = LogStaticString


public struct LogSourceLocation: Equatable, Hashable, Sendable, CustomStringConvertible {

  public let function: LogStaticString
  public let file: LogSourceFile
  public let line: UInt

  public init(function: LogStaticString, file: LogSourceFile, line: UInt) {
    self.function = function
    self.file = file
    self.line = line
  }

  public var description: String {
    "\(function) (\(file):\(line))"
  }

}

//
//  FunctionLogScope.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/28/25.
//


public struct FunctionLogScope: LogScope {

  public var function: LogStaticString
  public var file: LogSourceFile

  public init(function: LogStaticString, file: LogSourceFile) {
    self.function = function
    self.file = file
  }

  public init(function: StaticString, file: StaticString) {
    self.init(function: .init(function), file: .init(file))
  }

  public var name: String { "\(function)@\(file)" }

}

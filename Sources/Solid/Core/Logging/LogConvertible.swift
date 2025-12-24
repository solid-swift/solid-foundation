//
//  LogConvertible.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/28/25.
//


public protocol LogConvertible: Sendable {

  var logDescription: String { get }

}


extension LogConvertible where Self: CustomStringConvertible {

  public var logDescription: String { description }

}


extension LogConvertible where Self: CustomDebugStringConvertible {

  public var logDescription: String { debugDescription }

}


extension LogConvertible where Self: CustomStringConvertible, Self: CustomDebugStringConvertible {

  public var logDescription: String { debugDescription }

}

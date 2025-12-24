//
//  LogScope.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/28/25.
//


public protocol LogScope: Sendable {

  var name: String { get }

}


extension LogScope {

  public var name: String {
    String(describing: self)
  }

}

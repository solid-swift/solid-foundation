//
//  LogArgument.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/28/25.
//


public protocol LogArgument: Sendable {

  var constantValue: String { get }
  var formattedValue: String { get }
  var privacy: LogPrivacy { get }

}

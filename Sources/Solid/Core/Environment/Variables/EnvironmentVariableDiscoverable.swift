//
//  EnvironmentVariableDiscoverable.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/29/25.
//

public protocol EnvironmentVariableDiscoverable: EnvironmentVariableInitializable {

  static var environmentVariableNames: [String] { get }
  init?(environmentVariableValue: String)

  static func interrogateEnvironment(_ environment: ProcessEnvironment) -> Self?

  static var environmentDefaultValue: Self? { get }
}

extension EnvironmentVariableDiscoverable {

  public static func interrogateEnvironment(_ environment: ProcessEnvironment) -> Self? {
    return nil
  }

  public static var environmentDefaultValue: Self? {
    return nil
  }

}

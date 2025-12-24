//
//  BoolLogArgument.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/29/25.
//


public struct BoolLogArgument: LogArgument {

  public enum Format: Sendable {
    case `default`
    case truth
    case answer
  }

  public var value: @Sendable () -> Bool
  public var format: Format
  public var privacy: LogPrivacy

  public init(value: @escaping @Sendable () -> Bool, format: Format? = nil, privacy: LogPrivacy? = nil) {
    self.value = value
    self.format = format ?? .truth
    self.privacy = privacy ?? .public
  }

  public var constantValue: String {
    value().description
  }

  public var formattedValue: String {
    format.apply(self.value())
  }

}


public extension BoolLogArgument.Format {

  func apply(_ value: Bool) -> String {
    switch self {
    case .default, .truth: value.description
    case .answer: value ? "yes" : "no"
    }
  }

}

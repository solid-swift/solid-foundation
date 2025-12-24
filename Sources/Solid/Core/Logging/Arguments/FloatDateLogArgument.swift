//
//  FloatTimeArgument.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/29/25.
//

import Foundation


public struct FloatDateLogArgument<F: BinaryFloatingPoint & Sendable>: LogArgument {

  public enum Format: Sendable {
    case `default`
    case iso
    case short
    case long
  }

  public enum Epoch: Sendable {
    case unix
    case reference
  }

  public var float: @Sendable () -> F
  public var epoch: Epoch
  public var format: Format
  public var privacy: LogPrivacy

  public init(
    float: @escaping @Sendable () -> F,
    epoch: Epoch,
    format: Format? = nil,
    privacy: LogPrivacy? = nil
  ) {
    self.float = float
    self.epoch = epoch
    self.format = format ?? .default
    self.privacy = privacy ?? .public
  }

  private let constantFormatStyle = ConstantFormatStyles.for(TimeInterval.self)

  public var constantValue: String {
    epoch.apply(float()).timeIntervalSince1970.formatted(constantFormatStyle)
  }
  public var formattedValue: String { format.apply(epoch.apply(float())) }

}


extension FloatDateLogArgument.Format {

  public func apply(_ date: Date) -> String {
    switch self {
    case .default:
      date.formatted(date: .numeric, time: .standard)
    case .iso:
      date.formatted(.iso8601)
    case .short:
      date.formatted(date: .numeric, time: .shortened)
    case .long:
      date.formatted(date: .complete, time: .complete)
    }
  }

}


extension FloatDateLogArgument.Epoch {

  public func apply(_ float: F) -> Date {
    switch self {
    case .unix:
      Date(timeIntervalSinceReferenceDate: TimeInterval(float))
    case .reference:
      Date(timeIntervalSince1970: TimeInterval(float))
    }
  }

}

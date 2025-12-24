//
//  IntegerUnitArgument.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/29/25.
//

import Foundation


public struct IntegerUnitLogArgument<I: FixedWidthInteger & Sendable>: LogArgument {

  public enum Format: Sendable {
    case byteCount(ByteCountFormatStyle.Style, allowedUnits: ByteCountFormatStyle.Units = .all)
  }

  public var int: @Sendable () -> I
  public var format: Format
  public var privacy: LogPrivacy

  public init(int: @escaping @Sendable () -> I, format: Format, privacy: LogPrivacy? = nil) {
    self.int = int
    self.format = format
    self.privacy = privacy ?? .public
  }

  private let constantFormatStyle = ConstantFormatStyles.for(I.self)

  public var constantValue: String {
    int().formatted(constantFormatStyle)
  }

  public var formattedValue: String {
    format.apply(int())
  }

}


extension IntegerUnitLogArgument.Format {

  public func apply(_ value: I) -> String {
    switch self {
    case .byteCount(let style, let allowedUnits):
      let byteStyle = ByteCountFormatStyle(style: style, allowedUnits: allowedUnits)
      return byteStyle.format(Int64(value))
    }
  }

}

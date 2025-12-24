//
//  StringLogArgument.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/29/25.
//

import Foundation


public struct StringLogArgument<S: StringProtocol & Sendable>: LogArgument {

  public enum Format: Sendable {

    public enum Alignment: Sendable {
      case left
      case right
      case center
    }

    case `default`
    case fit
    case fixed(Int, alignment: Alignment = .left)
    case minimum(Int, alignment: Alignment = .left)
    case maximum(Int, alignment: Alignment = .left)
  }

  public var string: @Sendable () -> S
  public var format: Format
  public var privacy: LogPrivacy

  public init(
    string: @escaping @Sendable () -> S,
    format: Format? = nil,
    privacy: LogPrivacy? = nil
  ) {
    self.string = string
    self.format = format ?? .default
    self.privacy = privacy ?? .sensitive
  }

  public var constantValue: String {
    string().description
  }

  public var formattedValue: String {
    let string = string().description
    return switch format {
    case .default, .fit:
      string
    case .fixed(let width, let alignment):
      alignment.apply(string, width: width)
    case .minimum(let width, alignment: let alignment):
      if string.count >= width {
        string
      } else {
        alignment.apply(string, width: width)
      }
    case .maximum(let width, alignment: let alignment):
      if string.count <= width {
        string
      } else {
        alignment.apply(string, width: width)
      }
    }
  }

}


extension StringLogArgument.Format.Alignment {

  public func apply(_ value: String, width: Int) -> String {
    let diff = value.count - width
    if diff > 0 {
      return String(value.dropFirst(diff))
    } else if diff < 0 {
      switch self {
      case .left:
        let pad = String(repeating: " ", count: -diff)
        return "\(value)\(pad)"
      case .right:
        let pad = String(repeating: " ", count: -diff)
        return "\(pad)\(value)"
      case .center:
        let pad = String(repeating: " ", count: -diff / 2)
        return "\(pad)\(value)\(pad)"
      }
    } else {
      return value
    }
  }

}

//
//  Path-Selector-Slice.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/28/25.
//

extension Path.Selector {

  /// Slice selector defines a subset of values from an array.
  ///
  public struct Slice {
    /// The start index of the slice, or the start of the array if `nil`.
    var start: Int?
    /// The end index of the slice, or the end of the array if `nil`.
    var end: Int?
    /// The step size of the slice, or `1` if `nil`.
    var step: Int?
  }

}

extension Path.Selector.Slice: Sendable {}

extension Path.Selector.Slice: Hashable {}
extension Path.Selector.Slice: Equatable {}

extension Path.Selector.Slice: CustomStringConvertible {

  /// A description of the slice.
  ///
  public var description: String {
    var desc = ""
    if let start {
      desc += "\(start)"
    }
    desc += ":"
    if let end {
      desc += "\(end)"
    }
    if let step {
      desc += ":\(step)"
    }
    return desc
  }
}

//
//  ReplayRandomNumberGenerator.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/24/25.
//


public class ReplayRandomNumberGenerator: RandomNumberGenerator {

  public let numbers: [UInt64]
  public var index: Int = 0

  public init(_ numbers: [UInt64], index: Int = 0) {
    precondition(numbers.isEmpty == false, "Must supply at least one number")
    self.numbers = numbers
    self.index = index
  }

  public func next() -> UInt64 {
    defer { index = (index + 1) % numbers.count }
    return numbers[index]
  }

}

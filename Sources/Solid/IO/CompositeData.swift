//
//  CompositeData.swift
//  SolidIO
//
//  Created by Kevin Wooten on 7/4/25.
//

import Foundation


/// CompositeData accumulates multiple DataProtocol conforming elements without copying their data.
///
/// This allows you to efficiently treat multiple discrete DataProtocol values as a contiguous byte buffer,
/// conforming to DataProtocol. All operations are implemented by delegating to the underlying elements.
///
public struct CompositeData: DataProtocol {
  private var elements: [Data]

  public init(_ sequence: some Sequence<Data>) {
    self.elements = Array(sequence)
  }

  public init(_ elements: Data...) {
    self.elements = elements
  }

  public var count: Int {
    elements.reduce(0) { $0 + $1.count }
  }

  public var regions: [Data] {
    elements.flatMap { $0.regions }
  }

  public var startIndex: Int { 0 }
  public var endIndex: Int { count }

  public subscript(position: Int) -> UInt8 {
    return self[position..<position + 1].first.neverNil()
  }

  public subscript(bounds: Range<Int>) -> Data {
    precondition(bounds.lowerBound >= 0 && bounds.upperBound <= count)
    var lower = bounds.lowerBound
    var upper = bounds.upperBound
    var result = Data()
    for element in elements {
      let size = element.count
      if lower >= size {
        lower -= size
        upper -= size
        continue
      }
      let start = lower
      let end = Swift.min(size, upper)
      result.append(contentsOf: element[start..<end])
      lower = 0
      upper -= end
      if upper <= 0 { break }
    }
    return result
  }

  public func copyBytes(to pointer: UnsafeMutableRawBufferPointer) -> Int {
    var offset = 0
    var pointer = pointer
    for element in elements {
      let written = element.copyBytes(to: pointer)
      offset += written
      pointer = UnsafeMutableRawBufferPointer(rebasing: pointer.dropFirst(written))
      if pointer.isEmpty { break }
    }
    return offset
  }

  public mutating func append(_ element: Data) {
    elements.append(element)
  }
}

extension CompositeData: Equatable {}
extension CompositeData: Hashable {}

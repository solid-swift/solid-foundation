//
//  DataBufferPair.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation

/// Holds up to two buffers without allocating; merges when a third arrives.
struct DataBufferPair {
  private var storage: InlineArray<2, Data?> = InlineArray(repeating: nil)
  private var count: Int = 0

  mutating func append(_ data: Data) {
    guard !data.isEmpty else { return }
    if count == 0 {
      storage[0] = data
      count = 1
      return
    }
    if count == 1 {
      storage[1] = data
      count = 2
      return
    }
    var merged = Data()
    merged.append(storage[0] ?? Data())
    merged.append(storage[1] ?? Data())
    merged.append(data)
    storage[0] = merged
    storage[1] = nil
    count = 1
  }

  mutating func replace(with data: Data) {
    if data.isEmpty {
      storage[0] = nil
      storage[1] = nil
      count = 0
    } else {
      storage[0] = data
      storage[1] = nil
      count = 1
    }
  }

  func combinedData() -> Data {
    switch count {
    case 0:
      return Data()
    case 1:
      return storage[0] ?? Data()
    default:
      var merged = Data()
      merged.append(storage[0] ?? Data())
      merged.append(storage[1] ?? Data())
      return merged
    }
  }
}

//
//  CounterIDSource.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/20/25.
//


public struct CounterIDSource<S: CounterSource>: UniqueIDSource {

  public typealias ID = CounterID<S.Count>

  public var source: S
  public var salt: S.Count

  public init(source: S, salt: S.Count = S.Count.random(in: 0 ... .max)) {
    self.source = source
    self.salt = salt
  }

  public func generate() -> CounterID<S.Count> {
    do {
      var value = source.next() &+ salt
      return try withUnsafeBytes(of: &value) { ptr in
        try CounterID<S.Count> { out in
          for idx in 0..<MemoryLayout<S.Count>.size {
            out.append(ptr[idx])
          }
        }
      }
    } catch let e {
      fatalError("Failed to encode CounterID: \(e)")
    }
  }
}

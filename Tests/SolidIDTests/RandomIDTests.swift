//
//  RandomIDTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/20/25.
//

import Testing
import SolidID


@Suite struct RandomIDTests {

  @Test func generate() throws {
    let source = RandomIDSource<UInt>()
    let id = source.generate()
    #expect(id.description != "")
  }

  @Test func unique() throws {
    let source = RandomIDSource<UInt>()
    var prev = source.generate()
    for _ in 1..<500 {
      let next = source.generate()
      #expect(prev != next)
      prev = next
    }
  }

}

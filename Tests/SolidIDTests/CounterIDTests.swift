//
//  CounterIDTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/20/25.
//

import Testing
import SolidID


@Suite struct CounterIDTests {

  @Test func generate() async throws {
    let generator = CounterIDSource(source: AtomicCounterSource<UInt64>(), salt: 0)
    #expect(generator.generate().storage == 1)
    #expect(generator.generate().storage != 1)
  }

}

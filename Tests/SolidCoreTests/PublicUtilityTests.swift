//
//  PublicUtilityTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 8/15/26.
//

import SolidCore
import Testing

@Suite
struct PublicUtilityTests {

  private enum TestError: Error, Equatable {
    case missing
  }

  @Test
  func `unwrap returns a present value`() throws {
    let value: Int? = 42

    #expect(try value.unwrap() == 42)
  }

  @Test
  func `unwrap throws the supplied error`() {
    let value: Int? = nil

    #expect(throws: TestError.missing) {
      try value.unwrap(or: TestError.missing)
    }
  }

  @Test
  func `never nil returns a present value`() {
    let value: Int? = 42

    #expect(value.neverNil() == 42)
  }

  @Test
  func `never throw returns a successful value`() {
    let value = neverThrow(try Result<Int, TestError>.success(42).get())

    #expect(value == 42)
  }
}

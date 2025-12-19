//
//  BinaryEncodingTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 9/23/25.
//

import SolidCore
import Testing

@Suite
struct BinaryEncodingTests {

  @Suite
  struct Hex {

    @Test
    func `encode to string`() throws {

      let data: [UInt8] = [1, 2, 4, 8, 16, 32, 64, 128]

      let string = HexEncoding.default.encode(data)
      #expect(string == "0102040810204080")
    }

  }

}

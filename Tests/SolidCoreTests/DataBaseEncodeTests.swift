//
//  DataBaseEncodeTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 9/23/25.
//

import Foundation
import SolidCore
import Testing


@Suite
struct `Data baseEncode Tests` {

  @Suite
  struct Hex {

    @Test
    func `encode to string`() throws {

      let data: [UInt8] = [1, 2, 4, 8, 16, 32, 64, 128]

      let string = Data(data).baseEncoded(using: .base16)
      #expect(string == "0102040810204080")
    }
  }

  @Suite
  struct Crockford {

    @Test
    func `encode to string`() throws {
      let data: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf]
      let string = Data(data).baseEncoded(using: .base32Crockford)
      #expect(string == "041061050R3GG28A1C60T3GF")
    }
  }

}

//
//  ErrorTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 8/1/25.
//

@testable import SolidIO
import Testing


@Suite("IO Error Tests")
struct ErrorTests {

  @Test("IO Error Description")
  func ioErrorDescription() throws {
    #expect(IOError.endOfStream.errorDescription == "End of Stream")
    #expect(IOError.streamClosed.errorDescription == "Stream Closed")
    #expect(IOError.filterFailed(IOError.endOfStream).errorDescription == "Filter Failed: End of Stream")
  }

}

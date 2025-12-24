//
//  UUIDv4Tests.swift
//

import Testing
@testable import SolidID


@Suite struct `UUIDv4 Tests` {

  @Test func `version & variant`() {
    let u = UUID.v4()
    #expect(u.version == .v4)
    #expect(u.variant == .rfc)
  }
}

//
//  UUIDv4Tests.swift
//

import Testing
@testable import SolidID


@Suite struct UUIDv4Suite {

  @Test func versionAndVariant() {
    let u = UUID.v4()
    #expect(u.version == .v4)
    #expect(u.variant == .rfc)
  }
}

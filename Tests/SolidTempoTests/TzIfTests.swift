//
//  TzIfTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/4/25.
//

@testable import SolidTempo
import Foundation
import Testing


@Suite("TzIf Tests")
struct TzIfTests {

  let printMessages = false

  func zoneFileURL(_ identifier: String) -> URL {
    for url in TzDb.defaultZoneInfoUrls {
      let resolvedURL = url.resolvingSymlinksInPath()
      let dataURL = URL(fileURLWithPath: identifier, relativeTo: resolvedURL)
      guard (try? dataURL.checkResourceIsReachable()) == true else {
        continue
      }
      return dataURL
    }
    fatalError("No zone file URL found for identifier: \(identifier)")
  }

  @Test("Zone Info Discovery")
  func testZoneInfoDiscovery() throws {
    let db = TzDb(zoneInfoUrls: TzDb.defaultZoneInfoUrls)

    #expect(db.zones.count > 500)

    // Check for known zones of all different identifier formats
    #expect(db.zones["America/New_York"] != nil)
    #expect(db.zones["UTC"] != nil)
    #expect(db.zones["Etc/UTC"] != nil)
    #expect(db.zones["Etc/GMT+0"] != nil)
    #expect(db.zones["Etc/GMT-0"] != nil)

    // Check for more esoteric and edge-case timezones
    #expect(db.zones["America/Argentina/Buenos_Aires"] != nil)
    #expect(db.zones["Asia/Kolkata"] != nil)
    #expect(db.zones["Europe/London"] != nil)
    #expect(db.zones["Australia/Sydney"] != nil)
    #expect(db.zones["Pacific/Auckland"] != nil)
    #expect(db.zones["Africa/Cairo"] != nil)
    #expect(db.zones["Asia/Tokyo"] != nil)
    #expect(db.zones["Europe/Paris"] != nil)
    #expect(db.zones["America/Los_Angeles"] != nil)
    #expect(db.zones["Asia/Shanghai"] != nil)

    // Check for some special cases
    #expect(db.zones["GMT"] != nil)
    #expect(db.zones["Etc/GMT"] != nil)
    #expect(db.zones["Etc/GMT+1"] != nil)
    #expect(db.zones["Etc/GMT-1"] != nil)
    #expect(db.zones["Etc/GMT+12"] != nil)
    #expect(db.zones["Etc/GMT-12"] != nil)

    // Check for some historical/legacy zones
    #expect(db.zones["America/St_Johns"] != nil)
    #expect(db.zones["America/Godthab"] != nil)
    #expect(db.zones["Asia/Calcutta"] != nil)

    // Check that the each zone's rules are not actually loaded
    #expect(db.zones["America/New_York"]?.state.withLock { $0 == nil } == true)
    #expect(db.zones["UTC"]?.state.withLock { $0 == nil } == true)
  }

  @Test("Region based zone loading")
  func testRegionBasedZoneLoading() throws {
    let loader = TzDb.default

    let fZones = Set(TimeZone.knownTimeZoneIdentifiers)
    let tZones = Set(loader.zones.keys)
    echo("Zones not in TimeZone: \(fZones.subtracting(tZones))")
    echo("Zones not in TzIf: \(tZones.subtracting(fZones))")

    for zoneId in loader.zones.keys {
      echo("Loading \(zoneId)...")
      do {
        _ = try loader.load(identifier: zoneId)
        echo("- Successful")
      } catch {
        echo("- Failed: \(error)")
      }
    }
    echo("Loaded \(loader.zones.count) zones!")
  }

  func echo(_ message: String) {
    if printMessages {
      print(message)
    }
  }
}

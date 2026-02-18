//
//  TzDb.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/9/25.
//

import SolidCore
import Foundation
import Synchronization


/// ``ZoneRules`` provider for `tzdb`/`zoneinfo`.
///
/// During initialization, all available `TZif` files are discovered and prepared
/// for lazy loading in a static static dictionary cache. During discovery,
/// no loading or parsing of the associated file TZif files is completed. The
/// files are parsed, validated, and converted to ``ZoneRules``
/// on-demand when a request for the specific zone identifier is made.
///
/// ## Concurrency
/// The static zone entries dictionary ensiures unlocked access to all
/// previously loaded files. Locking only occurs when data for a specific
/// zone is being loaded. After loading, double checked locking is used to
/// ensure that the loading lock does not need to be held for each subsequent
/// access to the zone entry.
///
public final class TzDb: ZoneRulesLoader {

  internal static let log = LogFactory.for(type: TzDb.self)

  /// Errors related to loading ``ZoneRules`` from `zoneinfo` data.
  public enum Error: Swift.Error {
    case zoneInfoNotFound
    case unableToLoadZone(Swift.Error)
    case noVersionInZoneInfo
  }

  /// The default locations to search for `zoneinfo` data.
  public static let defaultZoneInfoUrls: [URL] = [
    URL(filePath: "/usr/share/zoneinfo/")
  ]

  // Possible names for  the `zoneinfo` .

  /// Name of the standard tzdata parameters file (which includes the version).
  public static let tzDataFileName = "tzdata.zi"
  /// Name of the legacy version stamp file.
  public static let versionFileName = "+VERSION"

  final class ZoneEntry: Sendable {

    final class State: Sendable {

      enum Value {
        case loaded(ZoneRules, parsed: TzIf.Rules?)
        case failed(Swift.Error)

        public var rules: ZoneRules {
          get throws {
            switch self {
            case .loaded(let rules, parsed: _):
              return rules
            case .failed(let error):
              throw error
            }
          }
        }
      }

      private let value: Value

      init(_ value: Value) {
        self.value = value
      }

      public var rules: ZoneRules {
        get throws {
          try value.rules
        }
      }
    }

    let url: URL
    let retainParsed: Bool
    let state = Mutex<State?>(nil)

    init(url: URL, retainParsed: Bool = false) {
      self.url = url
      self.retainParsed = retainParsed
    }

    func load() throws -> ZoneRules {
      try state.withLock { state in
        if let state {
          return try state.rules
        }

        // Load rules and initialize state
        let state: State
        do {
          let tzIfRules = try TzIf.load(url: url)
          let zoneRules = try TzIf.buildZoneRules(rules: tzIfRules)
          state = .init(.loaded(zoneRules, parsed: retainParsed ? tzIfRules : nil))
        } catch {
          state = .init(.failed(error))
        }

        return try state.rules
      }
    }
  }

  /// Default instance of ``TzDb`` that attempts to use the system provided
  /// `zoneinfo` directory.
  ///
  public static let `default` = TzDb(zoneInfoUrls: defaultZoneInfoUrls)

  /// URL of the resolved `zoneinfo` directory.
  public let url: URL

  /// Version of the `zoneinfo` data.
  public let version: String

  /// On-demand loader for each zone info data file.
  let zones: [String: ZoneEntry]

  /// Initializes a new `TzDb` with a list of possible `zoneinfo` URLs
  /// to initialize from.
  ///
  /// Initialization checks each provided URL for a proper `zoneinfo` structure,
  /// choosing the first valid directory found. If no valid directory is found, then
  /// the loader will be initialized as an "empty" database.
  ///
  /// During the `zoneinfo` directory is traversed for files matching the `TZif`
  /// format, and a cache entry is created for each file. The files are not loaded or
  /// parsed until a request for the specific zone identifier is made.
  ///
  /// - Parameters:
  ///   - zoneInfoUrls: A list of URLs to search for `zoneinfo` data.
  ///   - retainParsedRules: If `true`, the parsed ``TzIf/Rules``
  ///   data will be retained along with the ``ZoneRules`` implementation.
  ///   This is useful for debugging and testing, but increases memory usage.
  ///
  public init(zoneInfoUrls: [URL], retainParsedRules: Bool = false) {
    do {
      let (zoneInfoUrl, zoneInfoVersion, zoneInfoDataUrls) = try Self.discoverZoneInfo(urls: zoneInfoUrls)

      Self.log.debug("Discovered tzdb v\(zoneInfoVersion) at \(zoneInfoUrl) with \(zoneInfoDataUrls.count) zones")

      self.url = zoneInfoUrl
      self.version = zoneInfoVersion
      self.zones = Dictionary(uniqueKeysWithValues: zoneInfoDataUrls.map { ($0.relativePath, ZoneEntry(url: $0)) })

      if Self.log.isEnabled(for: .trace) {
        for (zoneId, zone) in zones {
          Self.log.debug("  - \(zoneId): \(zone.url)")
        }
      }

    } catch {
      Self.log.error("Failed to initialize \(Self.self): \(error)")
      self.url = URL(fileURLWithPath: "")
      self.version = ""
      self.zones = [:]
    }
  }

  /// Loads a ``ZoneRules`` implementation for the specified zone identifier.
  ///
  /// If the identifier is known, this method will load the zone rules from a pre-discovered
  /// zone info file, otherwise it will throw an error.
  ///
  /// - Note: This method is thread-safe and will only load the zone rules once, caching
  /// them for subsequent requests.
  ///
  public func load(identifier: String) throws -> any ZoneRules {
    guard let entry = zones[identifier] else {
      throw TempoError.invalidRegionalTimeZone(identifier: identifier)
    }
    return try entry.load()
  }

  /// Discover zone info files at any of the specified URLs.
  ///
  /// Each provided URL is checked for the presence of a valid `zoneinfo` directory.
  /// The first valid directory found is returned along with its version and list of data file
  /// URLs.
  ///
  private static func discoverZoneInfo(urls: [URL]) throws -> (url: URL, version: String, dataUrls: [URL]) {
    for url in urls {
      do {
        return try discoverZoneInfo(at: url)
      } catch {
        log.error("Failed to discover zone info files at \(url): \(error)")
        continue
      }
    }
    throw Error.zoneInfoNotFound
  }

  /// Discover zone info files at the specified URL.
  ///
  private static func discoverZoneInfo(
    at zoneInfoURL: URL
  ) throws -> (url: URL, version: String, dataUrls: [URL]) {
    let fileManager = FileManager.default

    var previousZoneInfoURL = zoneInfoURL
    var resolvedZoneInfoURL = zoneInfoURL
    repeat {
      previousZoneInfoURL = resolvedZoneInfoURL
      resolvedZoneInfoURL = zoneInfoURL.resolvingSymlinksInPath()
    } while resolvedZoneInfoURL != previousZoneInfoURL

    let version = try loadZoneInfoVersion(zoneInfoURL: zoneInfoURL)

    guard
      let contents = fileManager.enumerator(
        at: resolvedZoneInfoURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles, .producesRelativePathURLs]
      )
    else {
      Self.log.error("Failed to enumerate zone info files at \(resolvedZoneInfoURL)")
      return (resolvedZoneInfoURL, version, [])
    }

    #if os(Linux)
      // Manually relativize paths because linux FileManager
      // doesn't currently respect `producesRelativePathURLs` option
      let zoneContents = contents.map {
        URL(
          filePath: knownSafeCast($0, to: URL.self).path().replacingOccurrences(of: zoneInfoURL.path(), with: ""),
          relativeTo: zoneInfoURL
        )
      }
    #else
      let zoneContents = contents.compactMap { $0 as? URL }
    #endif

    var urls: [URL] = []
    for case let url in zoneContents where isZoneInfoFileLike(url) {
      urls.append(url)
    }

    return (resolvedZoneInfoURL, version, urls)
  }

  private static func isZoneInfoFileLike(_ url: URL) -> Bool {
    let fileName = url.lastPathComponent
    return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false
      && !fileName.hasPrefix("+")
      && !fileName.allSatisfy(\.isLowercase)
      && url.pathExtension.isEmpty
  }

  private static func loadZoneInfoVersion(zoneInfoURL: URL) throws -> String {
    if let version = loadZoneInfoVersionFromTzData(zoneInfoURL: zoneInfoURL) {
      return version
    }
    if let version = loadZoneInfoVersionFromVersion(zoneInfoURL: zoneInfoURL) {
      return version
    }
    throw Error.unableToLoadZone(Error.noVersionInZoneInfo)
  }

  private static func loadZoneInfoVersionFromTzData(zoneInfoURL: URL) -> String? {
    do {
      let tzDataURL = zoneInfoURL.appending(path: tzDataFileName)
      guard let tzDataHead = try FileHandle(forReadingFrom: tzDataURL).read(upToCount: 512) else {
        return nil
      }
      for lineData in tzDataHead.split(separator: "\n".utf8) {
        guard let line = String(data: lineData, encoding: .utf8) else { continue }
        guard let match = line.wholeMatch(of: /#\s+version\s+(\w+)/) else { continue }
        return String(match.output.1)
      }
      return nil
    } catch {
      return nil
    }
  }

  private static func loadZoneInfoVersionFromVersion(zoneInfoURL: URL) -> String? {
    do {
      let versionFileURL = zoneInfoURL.appending(path: versionFileName)
      let versionString = try String(contentsOf: versionFileURL, encoding: .utf8)
      return versionString.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      return nil
    }
  }

  /// Parses the `tzdata.zi` file to extract the valid start year and first transition year for each zone.
  ///
  /// The `tzdata.zi` file contains zone definitions in the format:
  /// `Z <zone_name> <offset> <rules> <format> [<until>]`
  /// followed by continuation lines for additional transitions.
  ///
  /// The `<until>` field (if present) indicates when the first transition starts,
  /// which represents the earliest year for which the zone has recorded data.
  ///
  /// - Returns: A dictionary mapping zone identifiers to a tuple of (validStartYear, firstTransitionYear).
  ///   The firstTransitionYear is the year of the first actual transition after the initial LMT period.
  ///
  public func loadZoneValidRanges() -> [String: (validStartYear: Int, firstTransitionYear: Int)] {
    do {
      let tzDataURL = url.appending(path: Self.tzDataFileName)
      let tzDataContent = try String(contentsOf: tzDataURL, encoding: .utf8)

      var validRanges: [String: (validStartYear: Int, firstTransitionYear: Int)] = [:]
      var currentZone: String?
      var currentStartYear: Int?
      var currentFirstTransitionYear: Int?

      for line in tzDataContent.split(separator: "\n") {
        if line.hasPrefix("Z ") {
          // Save previous zone if any
          if let zone = currentZone, let startYear = currentStartYear {
            validRanges[zone] = (startYear, currentFirstTransitionYear ?? startYear)
          }

          let parts = line.split(separator: " ", omittingEmptySubsequences: true)
          guard parts.count >= 2 else { continue }

          currentZone = String(parts[1])
          currentStartYear = nil
          currentFirstTransitionYear = nil

          // The year is typically the 5th field (index 4) if present
          // Format: Z <zone_name> <offset> <rules> <format> [<until>]
          if parts.count >= 5 {
            for i in 4..<parts.count {
              if let year = Int(parts[i]) {
                currentStartYear = year
                break
              }
            }
          }
        } else if currentZone != nil && !line.hasPrefix("#") && !line.hasPrefix("R ") && !line.hasPrefix("L ") {
          // This is a continuation line for the current zone
          // Format: <offset> <rules> <format> [<until>]
          let parts = line.split(separator: " ", omittingEmptySubsequences: true)
          if parts.count >= 3 && currentFirstTransitionYear == nil {
            // Find the year in this continuation line
            for i in 3..<parts.count {
              if let year = Int(parts[i]) {
                currentFirstTransitionYear = year
                break
              }
            }
          }
        }
      }

      // Save last zone
      if let zone = currentZone, let startYear = currentStartYear {
        validRanges[zone] = (startYear, currentFirstTransitionYear ?? startYear)
      }

      return validRanges
    } catch {
      Self.log.error("Failed to load zone valid ranges from tzdata.zi: \(error)")
      return [:]
    }
  }
}

extension ZoneRulesLoader where Self == TzDb {

  public static var system: Self { TzDb.default }

}

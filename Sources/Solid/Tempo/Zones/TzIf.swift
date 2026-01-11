//
//  TzIf.swift
//  Codex
//
//  Created by Kevin Wooten on 5/12/25.
//

import SolidCore
import Foundation
import Synchronization


private let log = LogFactory.for(type: TzIf.self)

/// TZif file parsing and validation.
///
public enum TzIf {

  public enum Error: Swift.Error {
    case invalidFooter
    case invalidPosixTZ
    case invalidDesignation
    case invalidLeapSecond
    case unsupportedFileVersion(version: UInt8)
    case noTransitions
    case typeIndexOutOfBounds
    case missingVersionData
    case wallStdUniversalDisagreement
    case transitionsNotOrdered
    case missingStandardTime
    case invalidLength
    case magicMismatch
    case stdOrUniversalCountMismatch
    case fieldLimitExceeded
  }

  public enum Version: UInt8 {
    case v1 = 0
    case v2 = 50
    case v3 = 51
    case v4 = 52
  }

  /// Parsed header data.
  public struct Header {
    let version: Version
    let isUTCount: Int
    let isStdCount: Int
    let leapCount: Int
    let timeCount: Int
    let typeCount: Int
    let charCount: Int
  }

  /// Parsed POSIX TZ rule string.
  ///
  /// This is a simplified representation of the rule that is used to
  /// parse the rule string.
  ///
  public struct PosixTZ: Sendable {
    public typealias DSTRule = (month: Int, week: Int, day: Int, time: Int)
    public typealias DSTRules = (start: DSTRule, end: DSTRule)

    public let raw: String
    public let std: (designation: String, offset: Int)
    public let dst: (designation: String, offset: Int, rules: DSTRules)?
  }

  public typealias ElementSizes = (
    version: Int,
    count: Int,
    time: Int,
    index: Int,
    timeType: Int,
    leapSecond: Int,
    indicator: Int
  )

  // Namespaces for version-specific implementations

  enum V1 {
    public static let elementSizes: ElementSizes = (
      version: 1,
      count: 4,
      time: 4,
      index: 1,
      timeType: 6,
      leapSecond: 8,
      indicator: 1
    )
  }

  enum V2 {
    public static let elementSizes: ElementSizes = (
      version: V1.elementSizes.version,
      count: V1.elementSizes.count,
      time: 8,
      index: V1.elementSizes.index,
      timeType: V1.elementSizes.timeType,
      leapSecond: 12,    // 8-byte timestamp + 4-byte correction
      indicator: V1.elementSizes.indicator
    )
  }

  enum V3 {
    public static let elementSizes = V2.elementSizes
  }

  enum V4 {
    public static let elementSizes = V2.elementSizes
  }

  /// TZif specific rule data for a single zone information file.
  ///
  /// This structure of TZif files is fairly well represented by the
  /// ``Rules`` type, expressing all the available information
  /// in version `1-4` of the TZif file format. It is meant to be
  /// an input to build higer level, more efficient, structures that
  /// are purpose built for specific use cases. For example,
  /// ``TzDb`` converts this information into an efficient
  /// ``ZoneRules`` implementation for providing the
  /// libraries time zone functionality.
  ///
  public struct Rules: Sendable {

    /// A transition from one offset to another at a specific point in time.
    ///
    /// Parsed from the TZif `transition times` table. The time is in UTC
    /// and paired with a `time type record`  via the ``typeIndex``
    /// property that indexes into the ``TzIf/Rules/types`` table.
    ///
    public struct Transition: Sendable {
      /// The transition time in seconds since the Unix epoch (as parsed from TZif).
      var timestamp: Int64
      /// Index into ``TzIf/Rules/types`` array.
      var typeIndex: Int
    }

    /// Represents a local time type with offset, daylight saving info, etc.
    ///
    /// Matches the TZif `local time type record`  structure:
    /// - `utoff`: offset from UTC in seconds.
    /// - `isdst`: whether this is a DST offset.
    /// - `desigidx`: byte index into the `time zone designations` string table.
    ///
    public struct TimeType: Sendable {

      /// Unspecified ``isStd`` indicators default to `false`, denoting wall-clock time.
      public static let isStdDefault = false
      /// Unspecified ``isUT`` indicators default to `false`, denoting local-time.
      public static let isUTDefault = false

      /// The offset from UTC.
      ///
      /// Matches `utoff` of a `time type record` in the TZif file.
      ///
      public var offset: Int32

      /// Whether the offset represents daylight saving time.
      ///
      /// Matches `isdst` of a `time type record` in the TZif file.
      ///
      public var isDST: Bool

      /// Byte Index into the designation character string table.
      ///
      /// Matches `desigidx` of a `time type record` in the TZif file.
      ///
      public var designationIndex: Int

      /// Whether this time type is based on standard time (vs wall time).
      ///
      /// This value is populated from a TZif file's
      /// `standar/wall-clock indicators` section.
      ///
      public var isStd: Bool? = nil

      /// Whether this time type is based on UTC (vs local).
      ///
      /// This value is populated from a TZif file's
      /// `UT/local indidcators` section.
      ///
      public var isUT: Bool? = nil
    }

    /// A leap second correction at a specific UTC instant.
    public struct LeapSecond: Sendable {
      /// The instant at which the leap second occurs.
      public var occurrence: Int64
      /// Total number of seconds to apply at this point (cumulative).
      public var correction: Int32
    }

    /// Decoded `transition time records`.
    public private(set) var transitions: [Transition]
    /// Decoded `local time type records`.
    public private(set) var types: [TimeType]
    /// Decoded `time zone designations`.
    ///
    /// In serialized data, the `desigidx` property of `time type record`
    /// is an _octet_ index into the buffer of strings. The decoded map is
    /// stored as a dictionary with by `desigidx` as the key and the
    /// parsed string as the value.
    ///
    public private(set) var designations: [Int: String]
    /// Decoded `leap-second records`.
    public private(set) var leapSeconds: [LeapSecond]
    /// Parsed POSIX rule data, e.g., DST rules beyond last transition.
    public var posixTZ: PosixTZ?
    /// If this ruleset represents a  fixed offset zone, i.e., no transitions.
    public var isFixedFormat: Bool { transitions.isEmpty && types.count == 1 }

    public init(
      transitions: [Transition],
      types: [TimeType],
      designations: [Int: String] = [:],
      leapSeconds: [LeapSecond] = [],
      posixTZ: PosixTZ? = nil
    ) {
      self.transitions = transitions
      self.types = types
      self.designations = designations
      self.leapSeconds = leapSeconds
      self.posixTZ = posixTZ
    }
  }

  /// RFC, Spec., and implementation defined limits for various TZif header and
  /// data fields that are checked during parsing.
  ///
  /// These implementation defined limits (e.g. ``transitionTimestampRange`` are
  /// used a means to detect corrupt, invalid, or excessively large files that could
  /// cause excessive memory allocation or parsing times. They should _not_
  /// constrain any public valid TZif files.
  ///
  public enum Limits {

    /// Range of allowed transition timestamps (from `Jan 1, 1000 UTC` to
    /// `Jan 1, 3000 UTC`).
    ///
    /// - Note: This is an **implementation** defined limit to detect
    ///   corrupt or invalid files and avoiding excessive memory allocation
    ///   and/or processing times associated with their parsing.
    ///
    public static let transitionTimestampRange = Limit<Int64>(
      "transition timestamp",
      "transitionTimestampRange",
      -30_610_224_000...32_503_680_000
    )
    /// Range of allowed transitions offsets (`±26 hours`).
    ///
    /// Range chosen to match RFC 9636's recommended
    /// [-24:59:59, +25:59:59] bound.  The format itself allows
    /// any 32-bit signed value other than -2^31.
    ///
    /// - Note: This is an **implementation** defined limit to detect
    ///   corrupt or invalid files and avoiding excessive memory allocation
    ///   and/or processing times associated with their parsing.
    ///
    public static let transitionOffsetRange = Limit<Int64>(
      "transition offset",
      "transitionOffsetRange",
      -89_999...93_599
    )
    /// Range of allowed lead second occurances (from `Jan 1, 1000 UTC` to
    /// `Jan 1, 3000 UTC`).
    ///
    /// - Note: This is an **implementation** defined limit to detect
    ///   corrupt or invalid files and avoiding excessive memory allocation
    ///   and/or processing times associated with their parsing.
    ///
    public static let leapSecondOccurranceRange = Limit<Int64>(
      "leap second occurrance",
      "leapSecondOccurranceRange",
      -30_610_224_000...32_503_680_000
    )
    /// Maximum number of allowed transition times allowed in a single file.
    ///
    /// - Note: This is an **implementation** defined limit to detect
    ///   corrupt or invalid files and avoiding excessive memory allocation
    ///   and/or processing times associated with their parsing.
    ///
    public static let maxNumberOfTransitionTimes = Limit<Int>(
      "transition time count",
      "maxNumberOfTransitionTimes",
      0...200_000    // ~4MB of 64-bit timestamps
    )
    /// Maximum number of local time types allowed.
    ///
    /// - Note: This limit is currently imposed by the TZif format
    ///   due to the use of a single byte for the type index.
    ///
    public static let maxNumberOfLocalTimeTypes = Limit<Int>(
      "local time type count",
      "maxNumberOfLocalTimeTypes",
      0...255    // Limit imposed by TZif format (1 byte for type index)
    )
    /// Maximum number of designation characters allowed.
    ///
    /// - Note: This is an **implementation** defined limit to detect
    ///   corrupt or invalid files and avoiding excessive memory allocation
    ///   and/or processing times associated with their parsing.
    ///
    public static let maxNumberOfDesignationCharacters = Limit<Int>(
      "designation characters count",
      "maxNumberOfDesignationCharacters",
      0...16_384    // 64 characters for each of 255 time types (without overlap compression)
    )
    /// Maximum number of leap seconds allowed.
    ///
    /// - Note: This is an **implementation** defined limit to detect
    ///   corrupt or invalid files and avoiding excessive memory allocation
    ///   and/or processing times associated with their parsing.
    ///
    public static let maxNumberOfLeapSeconds = Limit<Int>(
      "leap seconds count",
      "maxNumberOfLeapSeconds",
      0...2_000    // Plenty for leap‑second history
    )

  }

  /// Loads a TZif file from the specified URL.
  ///
  /// - Parameters:
  ///  - url: The URL of the TZif file to load.
  /// - Returns: The parsed rules from the TZif file.
  /// - Throws: An error if the file cannot be located or parsed.
  ///
  public static func load(url: URL) throws -> Rules {

    let rules = try Data(contentsOf: url)
      .withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in

        var buf = ReadableRawBuffer(buffer)

        let header = try Header.parse(from: &buf)

        let verHeader: Header

        if header.version == .v1 {

          verHeader = header

        } else {

          let dataSize = versionDataSize(for: header, using: V1.elementSizes)

          // Check for minimal vs. standard form
          if try Header.checkMagic(buf, offset: dataSize) == false {
            // Minimal form

            guard header.timeCount == 0 && header.leapCount == 0 else {
              log.error("Invalid TZif file: missing version data (minimal form requires no times/leap-seconds")
              throw Error.missingVersionData
            }

            // Use main header
            verHeader = header

          } else {
            // Standard form

            // Skip v1 header/data & parse seond header
            try buf.skip(dataSize)
            verHeader = try Header.parse(from: &buf)
          }
        }

        let rules =
          switch header.version {
          case .v1: try V1.parse(data: &buf, header: verHeader)
          case .v2: try V2.parse(from: &buf, header: verHeader)
          case .v3: try V3.parse(from: &buf, header: verHeader)
          case .v4: try V4.parse(from: &buf, header: verHeader)
          }

        return rules
      }

    try validate(rules: rules)

    return rules
  }

  static func validate(rules: Rules) throws {
    let transitions = rules.transitions
    let types = rules.types
    let designations = rules.designations

    guard transitions.count > 0 || types.count == 1 else {
      log.error("Invalid TZif file: no transitions found data doesn't match a fixed zone")
      throw Error.noTransitions
    }

    // Validate all transition indices & timestamps
    for transition in transitions {

      try Limits.transitionTimestampRange.check(transition.timestamp)

      guard transition.typeIndex < types.count else {
        log.error(
          "Invalid TZif file: transition type index \(transition.typeIndex) out of bounds (max \(types.count - 1))"
        )
        throw Error.typeIndexOutOfBounds
      }
    }

    // Validate all time type designation indices, offsets, and DST/Std/UT combinations
    for type in types {

      try Limits.transitionOffsetRange.check(type.offset)

      // Validate designation
      guard let designation = designations[type.designationIndex] else {
        let validIndices = designations.keys.sorted()
        log.error(
          """
          Invalid TZif file: designation associated with index '\(type.designationIndex)' not found \
          (valid indices are \(validIndices))
          """
        )
        throw Error.invalidDesignation
      }
      guard Self.validateDesignation(designation) else {
        log.error("Invalid TZif file: invalid designation format '\(designation, privacy: .public)'")
        throw Error.invalidDesignation
      }

      // Validate DST and Std/UT combinations
      if type.isStd != nil || type.isUT != nil {
        let isStd = type.isStd ?? Rules.TimeType.isStdDefault
        let isUT = type.isUT ?? Rules.TimeType.isUTDefault

        // All UT times must be standard as well
        if isUT && !isStd {
          let utSpec = type.isUT == nil ? "defaulted" : "explicitly set"
          let stdSpec = type.isStd == nil ? "defaulted" : "explicitly set"
          log.error("Invalid TZif file: time type marked as UT (\(utSpec)) but not as STD (\(stdSpec))")
          throw Error.wallStdUniversalDisagreement
        }
      }
    }

    // Validate transition timestamps are strictly increasing and in plausible range
    for (transitionIdx, transition) in transitions.enumerated() {
      let ts = transition.timestamp

      try Limits.transitionTimestampRange.check(ts)

      if transitionIdx > 0 {
        let previousTs = transitions[transitionIdx - 1].timestamp
        guard ts > previousTs else {
          log.error(
            "Invalid TZif file: transition timestamp \(ts) not strictly increasing (previous: \(previousTs))"
          )
          throw Error.transitionsNotOrdered
        }
      }
    }

    // Ensure there is at least one standard time entry
    let stdCount = types.filter { !$0.isDST }.count
    guard stdCount > 0 else {
      log.error("Invalid TZif file: no standard time entries found")
      throw Error.missingStandardTime
    }
  }

  /// Validates a time zone designation string.
  private static func validateDesignation(_ designation: String) -> Bool {
    // Angle‑bracket form e.g. "<-05>"  or "<CST>"  (v3+)
    let allowedChars = CharacterSet.alphanumerics
      .union(CharacterSet(charactersIn: "-+<>"))

    guard designation.unicodeScalars.allSatisfy({ allowedChars.contains($0) }) else {
      return false
    }

    // If angle brackets used, they must wrap the string and be balanced.
    guard designation.first == "<" else {
      // traditional form: 3‑6 length
      guard designation.count >= 3 && designation.count <= 6 else {
        return false
      }
      return true
    }
    guard designation.last == ">", designation.count >= 3 else {
      return false
    }
    let inner = designation.dropFirst().dropLast()
    // inner part must be 1‑6 alnum / ±
    return inner.count >= 1 && inner.count <= 6
      && inner.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "+" }
  }

  static func buildZoneRules(rules: Rules) throws -> any ZoneRules {
    // Build the zone rules from parsed rules.
    guard !rules.isFixedFormat else {
      // Use the fixed format ZoneRules implementation.
      return buildFixedOffsetZoneRules(rules: rules)
    }

    return buildRegionZoneRules(rules: rules)
  }

  static func buildFixedOffsetZoneRules(rules: Rules) -> FixedOffsetZoneRules {
    precondition(
      rules.transitions.isEmpty && rules.types.count == 1,
      "Fixed offset rules should have not transitions and only a single type"
    )

    let fixedOffset = ZoneOffset(availableComponents: [.zoneOffset(Int(rules.types[0].offset))])
    return FixedOffsetZoneRules(offset: fixedOffset)
  }

  static func buildRegionZoneRules(rules: Rules) -> RegionZoneRules {
    precondition(
      !rules.isFixedFormat,
      "Fixed offset rules should be handled by buildFixedOffsetZoneRules"
    )

    let allTransitions = buildZoneTransitions(rules: rules)
    let initial = buildZoneOffset(type: rules.types[0])
    let final = buildZoneOffset(type: rules.types[rules.types.endIndex - 1])
    let tailRule = rules.posixTZ.map { buildZoneTransitionRule(tz: $0) }
    let designationMap = buildDesignationMap(
      transitions: allTransitions.map(\.transition),
      initial: rules.designations[rules.types[0].designationIndex].neverNil("Previously validated"),
      projectedDesignationSeed: tailRule?.standardTime.designation
    )

    let transitions = allTransitions.filter(\.isRequired).map(\.transition)

    return RegionZoneRules(
      initial: initial,
      final: final,
      transitions: transitions,
      tailRule: tailRule,
      designationMap: designationMap
    )
  }

  private static func buildZoneTransitionRule(tz: PosixTZ) -> ZoneTransitionRule {

    // POSIX-TZ are inverted in comparison to TZif/ISO
    let stdOffset = -tz.std.offset

    let std = ZoneTransitionRule.StandardTime(
      offset: ZoneOffset(availableComponents: [.zoneOffset(stdOffset)]),
      designation: tz.std.designation,
      isStandardTime: true
    )

    let dst: ZoneTransitionRule.DaylightSavingTime? = tz.dst.map { dst in
      // POSIX-TZ are inverted
      let dstOffset = -dst.offset

      return ZoneTransitionRule.DaylightSavingTime(
        offset: ZoneOffset(availableComponents: [.zoneOffset(dstOffset)]),
        designation: dst.designation,
        startRule: convertPosixRule(dst.rules.start),
        endRule: convertPosixRule(dst.rules.end)
      )
    }

    return ZoneTransitionRule(standardTime: std, daylightSavingTime: dst)
  }

  private static func buildDesignationMap(
    transitions: [ZoneTransition],
    initial: String,
    projectedDesignationSeed: String?
  ) -> [Instant: String] {

    var designationMap: [Instant: String] = [:]
    designationMap[.init(durationSinceEpoch: .min)] = initial

    for transition in transitions {
      designationMap[transition.instant] = transition.designation
    }

    // Add the projected designation if available
    if let projectedDesignation = projectedDesignationSeed {
      designationMap[.min] = projectedDesignation
    }

    return designationMap
  }

  private static func buildZoneOffset(type: Rules.TimeType) -> (offset: ZoneOffset, isStandardTime: Bool) {

    let offset = ZoneOffset(availableComponents: [.zoneOffset(Int(type.offset))])
    let isStandardTime = !type.isDST
    return (offset, isStandardTime)
  }

  private static func buildZoneTransitions(
    rules: Rules,
  ) -> [(transition: ZoneTransition, isRequired: Bool)] {

    var transitions: [(transition: ZoneTransition, isRequired: Bool)] = []
    transitions.reserveCapacity(rules.transitions.count)

    for (idx, ruleTransition) in rules.transitions.enumerated() {

      let toType = rules.types[ruleTransition.typeIndex]
      let fromType =
        idx == 0
        ? rules.types[0]    // initial type “before” first transition
        : rules.types[rules.transitions[idx - 1].typeIndex]

      let designation = rules.designations[toType.designationIndex].neverNil("Previously validated")

      let transition = buildZoneTransition(
        transition: ruleTransition,
        fromType: fromType,
        toType: toType,
        designation: designation
      )

      let isRequired = transition.before.offset != transition.after.offset || fromType.isDST != toType.isDST

      transitions.append((transition, isRequired))
    }

    return transitions
  }

  private static func buildZoneTransition(
    transition: Rules.Transition,
    fromType: Rules.TimeType,
    toType: Rules.TimeType,
    designation: String,
  ) -> ZoneTransition {
    let calSys: GregorianCalendarSystem = .default

    let instant = Instant(durationSinceEpoch: .seconds(transition.timestamp))
    let offsetBefore = ZoneOffset(availableComponents: [.zoneOffset(Int(fromType.offset))])
    let offsetAfter = ZoneOffset(availableComponents: [.zoneOffset(Int(toType.offset))])
    let kind: ZoneTransition.Kind = offsetBefore < offsetAfter ? .gap : .overlap

    let localBefore = calSys.localDateTime(instant: instant, at: offsetBefore)
    let localAfter = calSys.localDateTime(instant: instant, at: offsetAfter)

    return ZoneTransition(
      kind: kind,
      instant: instant,
      offsetBefore: offsetBefore,
      offsetAfter: offsetAfter,
      localBefore: localBefore,
      localAfter: localAfter,
      designation: designation,
      isDaylightSavingTime: toType.isDST,
    )
  }

  private static func convertPosixRule(_ rule: PosixTZ.DSTRule) -> ZoneTransitionRule.DateRule {
    guard rule.month == 0 else {
      // Month-week-day format
      return .monthWeekDay(
        month: rule.month,
        week: rule.week,
        day: rule.day,
        dayOffset: .seconds(Int64(rule.time))
      )
    }
    // Julian day format
    return .julianDay(
      day: rule.day,
      leap: false,    // POSIX Jn format doesn't count leap days
      dayOffset: .seconds(Int64(rule.time))
    )
  }
}

extension TzIf.Header {

  private typealias Counts = (
    isUTCnt: Int32, isStdCnt: Int32, leapCnt: Int32,
    timeCnt: Int32, typeCnt: Int32, charCnt: Int32
  )

  private static let countFieldIntTypes: [any (ReadableRawBuffer.Integer).Type] = [
    Int32.self, Int64.self,
  ]

  private static let magic: [UInt8] = [0x54, 0x5A, 0x69, 0x66]
  private static let numberOfCounts = 6
  private static let elementSizes = TzIf.V1.elementSizes
  private static let fieldOffsets = (
    magic: 0,    // [0..<4]
    version: 4,    // [4..<5]
    unused: 5,    // [5..<20]
    counts: 20,    // [20..<44]
    end: 44    // [44..<44]
  )

  fileprivate static func checkMagic(_ buf: ReadableRawBuffer<BigEndian>, offset: Int) throws -> Bool {
    return try buf.peekBytes(count: Self.magic.count, offsetBy: offset).elementsEqual(Self.magic)
  }

  fileprivate static func parse(
    from data: inout ReadableRawBuffer<BigEndian>
  ) throws -> Self {

    let hdrEnd = Self.fieldOffsets.end

    guard data.remaining.count >= hdrEnd else {
      let dataCount = data.count
      log.error(
        """
        Invalid TZif file: file too short \
        (received \(dataCount, format: .byteCount(.file)), requires at least \(hdrEnd, format: .byteCount(.file))
        """
      )
      throw TzIf.Error.invalidLength
    }

    let magic = try data.readBytes(count: 4)
    guard magic.elementsEqual(Self.magic) else {
      let received = Data(magic).baseEncoded(using: .base16)
      let expected = Data(Self.magic).baseEncoded(using: .base16)
      log.error(
        """
        Invalid TZif file: bad magic number: \(received, privacy: .public) \
        (expected \(expected, privacy: .public))
        """
      )
      throw TzIf.Error.magicMismatch
    }

    let rawVersion = try data.readInt(UInt8.self)
    guard let version = TzIf.Version(rawValue: rawVersion) else {
      log.error("Invalid TZif file: unsupported version \(rawVersion)")
      throw TzIf.Error.unsupportedFileVersion(version: rawVersion)
    }

    // Skip unused header data
    try data.skip(15)

    // Read each count and check its within limits

    let isUTCount = try data.readInt(UInt32.self, as: Int.self)
    let isStdCount = try data.readInt(UInt32.self, as: Int.self)
    let leapCount = try data.readInt(UInt32.self, as: Int.self)
    let timeCount = try data.readInt(UInt32.self, as: Int.self)
    let typeCount = try data.readInt(UInt32.self, as: Int.self)
    let charCount = try data.readInt(UInt32.self, as: Int.self)

    try TzIf.Limits.maxNumberOfTransitionTimes.check(timeCount)
    try TzIf.Limits.maxNumberOfLocalTimeTypes.check(typeCount)
    try TzIf.Limits.maxNumberOfLeapSeconds.check(leapCount)
    try TzIf.Limits.maxNumberOfDesignationCharacters.check(charCount)

    // Validate dependencies between fields
    guard isUTCount == 0 || isUTCount == typeCount else {
      log.error("Invalid TZif file: 'isutcnt' is \(isUTCount) (must be 0 or equal to 'typecnt' (\(typeCount))")
      throw TzIf.Error.stdOrUniversalCountMismatch
    }
    guard isStdCount == 0 || isStdCount == typeCount else {
      log.error("Invalid TZif file: 'isstdcnt' is \(isStdCount) (must be 0 or equal to 'typecnt' (\(typeCount))")
      throw TzIf.Error.stdOrUniversalCountMismatch
    }

    return Self(
      version: version,
      isUTCount: isUTCount,
      isStdCount: isStdCount,
      leapCount: leapCount,
      timeCount: timeCount,
      typeCount: typeCount,
      charCount: charCount,
    )
  }
}

extension TzIf {

  private static let timestampFieldIntTypes: [any (ReadableRawBuffer.Integer).Type] = [
    Int32.self, Int64.self,
  ]

  private static let occurranceFieldIntTypes = timestampFieldIntTypes

  fileprivate static func versionDataSize(for header: Header, using elementSizes: ElementSizes) -> Int {
    let transitions = header.timeCount * (elementSizes.time + elementSizes.index)
    let timeTypes = header.typeCount * elementSizes.timeType
    let designations = header.charCount
    let leapSeconds = header.leapCount * elementSizes.leapSecond
    let stdOrWallIndicators = header.isStdCount * elementSizes.indicator
    let utOrLocalIndicators = header.isUTCount * elementSizes.indicator
    return transitions + timeTypes + designations + leapSeconds + stdOrWallIndicators + utOrLocalIndicators
  }

  /// Common parsing function for V1 and V2 data, using the appropriate field sizes.
  fileprivate static func parse(
    from data: inout ReadableRawBuffer<BigEndian>,
    header: Header,
    using elementSizes: ElementSizes,
  ) throws -> Rules {

    let dataCount = data.remaining.count
    let requiredDataCount = versionDataSize(for: header, using: elementSizes)
    guard dataCount >= requiredDataCount else {
      log.error(
        """
        Invalid TZif file: file too short \
        (received \(dataCount, format: .byteCount(.file)), \
        data setion requires at least \(requiredDataCount, format: .byteCount(.file))
        """
      )
      throw TzIf.Error.invalidLength
    }

    // Read transition times

    var tsBuf = try data.readBuffer(count: header.timeCount * elementSizes.time)
    var ttiBuf = try data.readBuffer(count: header.timeCount * elementSizes.index)

    let tsIntType = Self.timestampFieldIntTypes[(elementSizes.time / 4) - 1]

    let transitions: [Rules.Transition] =
      try Array(unsafeUninitializedCapacity: header.timeCount) { buffer, initializedCount in
        for transitionIndex in 0..<header.timeCount {

          let timestamp = try tsBuf.readInt(tsIntType, as: Int64.self)
          let typeIndex = try ttiBuf.readInt(UInt8.self, as: Int.self)

          try Limits.transitionTimestampRange.check(timestamp)

          buffer.initializeElement(at: transitionIndex, to: .init(timestamp: timestamp, typeIndex: typeIndex))
          initializedCount = transitionIndex + 1
        }

        assert(tsBuf.remaining.isEmpty)
        assert(ttiBuf.remaining.isEmpty)
      }

    // Read time types
    var types: [Rules.TimeType] =
      try Array(unsafeUninitializedCapacity: header.typeCount) { buffer, initializedCount in
        for typeIndex in 0..<header.typeCount {

          let offset = try data.readInt(Int32.self)
          let isDST = try data.readBool(UInt8.self)
          let designationIndex = try data.readInt(UInt8.self, as: Int.self)

          try Limits.transitionOffsetRange.check(offset)

          buffer.initializeElement(
            at: typeIndex,
            to: .init(offset: offset, isDST: isDST, designationIndex: designationIndex)
          )
          initializedCount = typeIndex + 1
        }
      }

    // Designation string table
    let desigBuf = try data.readBuffer(count: header.charCount)

    // Parse designations, use start indices from time-types.
    //
    // WARN: You cannot use null-terminators to discover strings due to "overlap
    // compression" (my term) used by TZif files. Basically, the sequence "EDST\0"
    // could store 5 strings: "EDST", "DST", "ST", "T", and "" in the same space by
    // just using a different index into the buffer.

    var designations: [Int: String] = [:]
    for designationIndex in types.map(\.designationIndex).uniqued() {
      // Validate the designation index is within bounds
      guard designationIndex >= 0 && designationIndex < desigBuf.count else {
        log.error(
          "Invalid TZif file: designation index '\(designationIndex)' out of bounds (max \(desigBuf.count - 1))"
        )
        throw TzIf.Error.invalidDesignation
      }
      // Validate that a null-terminator (e.g. '\0') exists between designation-index
      // and the end of the designation data.
      let strStartIndex = desigBuf.index(desigBuf.startIndex, offsetBy: designationIndex)
      guard let strEndIndex = desigBuf[strStartIndex...].firstIndex(where: { $0 == 0 }) else {
        log.error("Invalid TZif file: designation at index '\(designationIndex)' not null terminated")
        throw TzIf.Error.invalidDesignation
      }
      // Build a UTF-8 string from the designation data (we skip the null terminator).
      let stringData = desigBuf[strStartIndex..<strEndIndex]
      guard let string = String(bytes: stringData, encoding: .utf8) else {
        log.error("Invalid TZif file: designation at index '\(designationIndex)' hss invalid UTF-8 data")
        throw TzIf.Error.invalidDesignation
      }
      designations[designationIndex] = string
    }

    // Read leap seconds

    let lsOccIntType = Self.timestampFieldIntTypes[elementSizes.leapSecond / 4 - 2]

    let leapSeconds: [Rules.LeapSecond] =
      try Array(unsafeUninitializedCapacity: header.leapCount) { buffer, initializedCount in
        for leapIndex in 0..<header.leapCount {

          let occurrence = try data.readInt(lsOccIntType, as: Int64.self)
          let correction = try data.readInt(Int32.self)

          try Limits.leapSecondOccurranceRange.check(occurrence)

          buffer.initializeElement(
            at: leapIndex,
            to: .init(occurrence: occurrence, correction: correction)
          )
          initializedCount = leapIndex + 1
        }
      }

    // Read isStd indicators
    for indIndex in 0..<header.isStdCount {
      types[indIndex].isStd = try data.readBool(UInt8.self)
    }
    // Read isUT indicators
    for indIndex in 0..<header.isUTCount {
      types[indIndex].isUT = try data.readBool(UInt8.self)
    }

    return Rules(
      transitions: transitions,
      types: types,
      designations: designations,
      leapSeconds: leapSeconds,
      posixTZ: nil
    )
  }

  /// Parses any footer after all versioned data, as a POSIX TZ string.
  private static func parsePOSIXFooter(
    from data: inout ReadableRawBuffer<BigEndian>,
    allowExtended: Bool,
  ) throws -> PosixTZ? {

    // Parse footer data to string
    guard let footer = try parseFooter(from: data) else {
      // No footer found
      return nil
    }

    return try TzIf.PosixTZ(string: footer, allowExtended: allowExtended)
  }

  /// Parses any footer string that appears after all versioned data.
  private static func parseFooter(from data: ReadableRawBuffer<BigEndian>) throws -> String? {
    let remaining = data.remaining

    // Empty or extraneous newlines are considered "no footer"
    guard !remaining.isEmpty, !remaining.trimming(while: { $0 == 0x0A }).isEmpty else {
      return nil
    }

    // Validate the would be footer is wrapped in newlines
    guard remaining.count > 1, remaining.first == 0xA && remaining.last == 0xA else {
      log.error("Invalid TZif file: footer not wrapped in newlines")
      throw TzIf.Error.invalidFooter
    }

    let stringData = remaining.dropFirst().dropLast()
    guard let string = String(bytes: stringData, encoding: .utf8) else {
      log.error("Invalid TZif file: footer not UTF-8 encoded")
      throw TzIf.Error.invalidFooter
    }

    return string
  }
}

extension TzIf.V1 {

  /// Parses TZif v1 data.
  fileprivate static func parse(
    data: inout ReadableRawBuffer<BigEndian>,
    header: TzIf.Header,
  ) throws -> TzIf.Rules {

    return try TzIf.parse(
      from: &data,
      header: header,
      using: Self.elementSizes
    )
  }
}

extension TzIf.V2 {

  // Parses TZif v2 data.
  fileprivate static func parse(
    from data: inout ReadableRawBuffer<BigEndian>,
    header: TzIf.Header,
  ) throws -> TzIf.Rules {

    var rules = try TzIf.parse(
      from: &data,
      header: header,
      using: Self.elementSizes
    )

    guard let posixTZ = try TzIf.parsePOSIXFooter(from: &data, allowExtended: false) else {
      // No footer found
      return rules
    }

    rules.posixTZ = posixTZ
    return rules
  }
}

extension TzIf.V3 {

  /// Parses TZif v3 data.
  fileprivate static func parse(
    from data: inout ReadableRawBuffer<BigEndian>,
    header: TzIf.Header,
  ) throws -> TzIf.Rules {

    var rules = try TzIf.parse(
      from: &data,
      header: header,
      using: Self.elementSizes
    )

    rules.posixTZ = try TzIf.parsePOSIXFooter(from: &data, allowExtended: true)

    return rules
  }
}

extension TzIf.V4 {

  /// Parses TZif v4 data.
  fileprivate static func parse(
    from data: inout ReadableRawBuffer<BigEndian>,
    header: TzIf.Header,
  ) throws -> TzIf.Rules {

    let calendar: GregorianCalendarSystem = .default

    // Parse using v2 format first
    var rules =
      try TzIf.parse(
        from: &data,
        header: header,
        using: Self.elementSizes
      )

    // Parse extended POSIX TZ string from footer, if present.
    rules.posixTZ = try TzIf.parsePOSIXFooter(from: &data, allowExtended: true)

    // Validate leap seconds
    for leapSecond in rules.leapSeconds {

      // Ensure leap seconds are at the end of UTC calendar months
      let instant = Instant(durationSinceEpoch: .seconds(leapSecond.occurrence))
      let dateTime: LocalDateTime = calendar.localDateTime(instant: instant, at: .utc)
      let lastDayOfMonth = calendar.range(of: .dayOfMonth, at: instant).upperBound

      guard dateTime[.dayOfMonth] == lastDayOfMonth else {
        let day = dateTime[.dayOfMonth] ?? 0
        log.error("Invalid TZif file: leap second not at end of month (day \(day)")
        throw TzIf.Error.invalidLeapSecond
      }

      guard dateTime[.hourOfDay] == 23 && dateTime[.minuteOfHour] == 59 && dateTime[.secondOfMinute] == 59 else {
        let hour = dateTime[.hourOfDay] ?? 0
        let minute = dateTime[.minuteOfHour] ?? 0
        let second = dateTime[.secondOfMinute] ?? 0
        log.error("Invalid TZif file: leap second not at 23:59:59 (got \(hour):\(minute):\(second))")
        throw TzIf.Error.invalidLeapSecond
      }
    }

    return rules
  }
}

// MARK: - POSIX TZ String Parsing

extension TzIf.PosixTZ {

  public init(string: String, allowExtended: Bool) throws {

    // - Split into std/dst & rule sections

    let tokens = string.split(separator: ",", omittingEmptySubsequences: false)
    let stdDstToken = tokens[0]
    let ruleTokens = tokens.dropFirst()

    // - std and optional dst parsing

    // parse std designation & offset
    var remainder = stdDstToken
    let stdDesig: String
    let stdOffSub: Substring
    (stdDesig, stdOffSub, remainder) = Self.splitNameOffset(remainder)
    // Use specified offset or default to `0`
    let stdOffset = try Self.parseOffset(stdOffSub, allowExtended: allowExtended) ?? 0

    // Parse optional dst designation & offset
    let dstBase: (desig: String, offset: Int)?
    if !remainder.isEmpty {
      let dName: String
      let dOffSub: Substring
      (dName, dOffSub, remainder) = Self.splitNameOffset(remainder)
      let dstName = dName
      // Use specified offset or default to 1 hour earlier
      let dstOffset = try Self.parseOffset(dOffSub, allowExtended: allowExtended) ?? (stdOffset - 3600)
      dstBase = (dstName, dstOffset)
    } else {
      dstBase = nil
    }

    // - transition rules

    let dstRules: (start: (Int, Int, Int, Int), end: (Int, Int, Int, Int))?
    if ruleTokens.count == 2, let startRuleToken = ruleTokens.first, let endRuleToken = ruleTokens.last {
      let startRule = try Self.parseTransitionRule(startRuleToken, allowExtended: allowExtended)
      let endRule = try Self.parseTransitionRule(endRuleToken, allowExtended: allowExtended)
      dstRules = (startRule, endRule)
    } else if ruleTokens.isEmpty {
      dstRules = nil
    } else {
      log.error("Invalid TZif file: transition rule specification must consist of exactly two rules")
      throw TzIf.Error.invalidPosixTZ
    }

    // DST must be fully specified or not at all
    let dst: (designation: String, offset: Int, rules: DSTRules)?
    if let dstBase {
      guard let dstRules else {
        log.error("Invalid TZif file: POSIX TZ DST specification requires transition rules")
        throw TzIf.Error.invalidPosixTZ
      }
      dst = (dstBase.0, dstBase.1, (start: dstRules.0, end: dstRules.1))
    } else {
      guard dstRules == nil else {
        log.error("Invalid TZif file: POSIX TZ DST specification requires a name & offset")
        throw TzIf.Error.invalidPosixTZ
      }
      dst = nil
    }

    self.raw = string
    self.std = (stdDesig, stdOffset)
    self.dst = dst
  }

  // MARK: – Internal helpers for POSIX-TZ parsing

  /// Parse an offset in the form `[+|-]hh[:mm[:ss]]`.
  ///
  /// Returns `nil` if empty and throws an error for any malformation.
  ///
  private static func parseOffset(_ s: Substring, allowExtended: Bool) throws -> Int? {

    guard !s.isEmpty else {
      return nil
    }

    let sign = s.first == "-" ? -1 : 1
    var body = s
    if s.first == "+" || s.first == "-" { body = s.dropFirst() }

    let parts = body.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count <= 3, let h = Int(parts[0]) else {
      log.error("Invalid TZif file: POSIX TZ offset is malformed")
      throw TzIf.Error.invalidPosixTZ
    }
    if allowExtended {
      guard h <= 167 else {
        log.error("Invalid TZif file: POSIX TZ extended offset hours must not exceed ±167")
        throw TzIf.Error.invalidPosixTZ
      }
    } else {
      guard h <= 24 else {
        log.error("Invalid TZif file: POSIX TZ offset hours must not exceed ±24 unless extended form is allowed")
        throw TzIf.Error.invalidPosixTZ
      }
    }

    let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
    let sec = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
    guard m < 60, sec < 60 else {
      log.error("Invalid TZif file: POSIX TZ offset minutes and seconds must be less than 60")
      throw TzIf.Error.invalidPosixTZ
    }
    return sign * (h * 3600 + m * 60 + sec)
  }

  /// Split a "NAMEoffset" or "<NAME>offset" token into separate strings.
  ///
  /// Returns the name, the *numeric* offset prefix (excluding any trailing letters), and any unprocessed characters.
  private static func splitNameOffset(_ tok: Substring) -> (String, Substring, Substring) {
    // Handle <NAME>
    if tok.first == "<", let end = tok.firstIndex(of: ">") {
      let name = tok[tok.index(after: tok.startIndex)..<end]
      let rest = tok[tok.index(after: end)...]
      // extract numeric offset prefix
      let offEnd = rest.firstIndex(where: { !($0.isNumber || $0 == ":" || $0 == "+" || $0 == "-") }) ?? rest.endIndex
      let offSub = rest[..<offEnd]
      return (String(name), offSub, rest[offEnd...])
    }

    // Traditional alpha name
    let nameEnd = tok.firstIndex(where: { $0 == "+" || $0 == "-" || $0.isNumber }) ?? tok.endIndex
    let name = tok[..<nameEnd]
    let rest = tok[nameEnd...]
    let offEnd: Substring.Index =
      rest.firstIndex(where: { !($0.isNumber || $0 == ":" || $0 == "+" || $0 == "-") }) ?? rest.endIndex
    let offSub = rest[..<offEnd]
    return (String(name), offSub, rest[offEnd...])
  }

  private static func parseTransitionRule(
    _ rule: Substring,
    allowExtended: Bool,
  ) throws -> (month: Int, week: Int, day: Int, time: Int) {

    // - Split into date and time portions

    let split = rule.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    let dateToken = split[0]
    let timeToken = split.count == 2 ? split[1] : Substring()

    // - Parse (optional) time field (shared by all date formats)

    let timeSeconds: Int
    if !timeToken.isEmpty {
      // Allow extended format when offset is for a rule
      guard let secs = try? Self.parseOffset(timeToken[...], allowExtended: true) else {
        log.error("Invalid TZif file: POSIX TZ transition rule '/time' is malformed")
        throw TzIf.Error.invalidPosixTZ
      }
      // Check range (extended outside all possible by wide marging but check for sanity)
      guard (-216_000...216_000).contains(secs) else {
        log.error("Invalid TZif file: POSIX TZ '/time' value \(secs) out of range ±60h")
        throw TzIf.Error.invalidPosixTZ
      }
      timeSeconds = secs
    } else {
      // Rule with no `/time` defaults to `02:00:00`
      timeSeconds = 3600 * 2
    }

    // - Parse the date portion

    // M-month.week.day
    if dateToken.hasPrefix("M") {
      let parts = dateToken.dropFirst().split(separator: ".")
      guard
        parts.count == 3,
        let month = Int(parts[0]), (1...12).contains(month),
        let week = Int(parts[1]), (1...5).contains(week),
        let weekday = Int(parts[2]), (0...6).contains(weekday)
      else {
        log.error("Invalid TZif file: POSIX TZ transition rule '\(rule)' has invalid Month-week-day format")
        throw TzIf.Error.invalidPosixTZ
      }
      return (month, week, weekday, timeSeconds)
    }

    // Julian no-leap  Jn
    if dateToken.hasPrefix("J") {
      guard
        let n = Int(dateToken.dropFirst()),
        1...365 ~= n
      else {
        log.error("Invalid TZif file: POSIX TZ transition rule '\(rule)' has invalid Julian format")
        throw TzIf.Error.invalidPosixTZ
      }
      // month 0 denotes ordinal form
      return (0, 0, n, timeSeconds)
    }

    // Day-of-year n[/time]
    if let n = Int(dateToken) {
      guard 0...365 ~= n else {
        log.error("Invalid TZif file: POSIX TZ transition rule '\(rule)' has invalid day-of-year format")
        throw TzIf.Error.invalidPosixTZ
      }
      return (0, 0, n, timeSeconds)
    }

    log.error("Invalid TZif file: POSIX TZ transition rule '\(rule)' has unknown format")
    throw TzIf.Error.invalidPosixTZ
  }

}

extension TzIf.Limits {

  public struct Limit<Bound: Sendable & SignedInteger>: Sendable {
    let specFieldName: String
    let limitPropertyName: String
    let range: ClosedRange<Bound>

    init(_ specFieldName: String, _ limitPropertyName: String, _ range: ClosedRange<Bound>) {
      self.specFieldName = specFieldName
      self.limitPropertyName = limitPropertyName
      self.range = range
    }

    func check<I: SignedInteger & Sendable>(_ value: I) throws {
      if let checkValue = Bound(exactly: value), range.contains(checkValue) {
        return
      }
      let range =
        range.lowerBound == 0
        ? "must be less than the allowed maximum of \(range.upperBound)"
        : "is outside the allowed range of \(range.lowerBound)...\(range.upperBound)"
      log.error(
        """
        TzIf Parse limit exceeded: \(specFieldName, privacy: .public) value \
        '\(value, privacy: .public)' \(range, privacy: .public).
        If the value is considered valid, check it against the limit \(limitPropertyName, privacy: .public) of \
        \(TzIf.Limits.self, privacy: .public) (in \(#file, privacy: .public)) and adjust accordingly \
        or submit an issue.
        """
      )
      throw TzIf.Error.fieldLimitExceeded
    }
  }

}

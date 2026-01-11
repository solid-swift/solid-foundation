//
//  CalendarSystem.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/29/25.
//

/// An immutable computation engine for a specific type of calender
/// (e.g., Gregorian, Islamic, etc.).
///
/// The major purpose of a ``CalendarSystem`` is to convert between
/// ``Instant`` values and ``DateTime`` values (e.g.,
/// ``ZonedDateTime`` and ``OffsetDateTime``) as well as to provide
/// calendar-specific components.
///
public protocol CalendarSystem {

  /// Computes a set of components for the given `Instant` in the specified time zone.
  ///
  /// - Parameters:
  ///   - instant: The instant to convert.
  ///   - zone: The time zone of instant.
  ///   - type: The type of container to convert to.
  /// - Returns: A set of components representing the instant in the specified time zone.
  /// - Throws: An error if the conversion fails or the components are invalid.
  ///
  func components<C>(from instant: Instant, in zone: Zone, as type: C.Type) throws -> C where C: ComponentBuildable

  /// Resolves the given components to a valid set of equivalent components.
  ///
  /// - Parameters:
  ///   - components: The components to resolve.
  ///   - resolution: The resolution strategy to use.
  /// - Returns: A valid set of components.
  /// - Throws: An error if the components cannot be resolved.
  ///
  func resolve<C, S>(
    components: S,
    resolution: ResolutionStrategy
  ) throws -> C where S: ComponentContainer, C: ComponentBuildable

  /// Looks up or computes the a requested component from a set of components.
  ///
  /// - Parameters:
  ///   - component: The component to resolve.
  ///   - components: The set of components to resolve from.
  ///   - resolution: The resolution strategy to use.
  /// - Returns: The resolved component value.
  /// - Throws: An error if the component cannot be resolved.
  ///
  func component<C, S>(
    _ component: C,
    from components: S,
    resolution: ResolutionStrategy
  ) throws -> C.Value where C: DateTimeComponentKind, S: ComponentContainer

  /// Computes the corresponding `Instant` for the specified components.
  ///
  /// - Parameters:
  ///   - components: The components to convert.
  ///   - resolution: The resolution strategy to use.
  /// - Returns: The instant corresponding to the components.
  /// - Throws: An error if the instant cannot be computed.
  ///
  func instant(from components: some ComponentContainer, resolution: ResolutionStrategy) throws -> Instant

  /// Computes the corresponding `Instant` for the specified date/time components using a specific zone offset.
  ///
  /// - Parameters:
  ///   - dateTime: The date/time to convert.
  ///   - offset: The zone offset to use for the computation.
  /// - Returns: The instant corresponding to the date/time at the specified offset.
  ///
  func instant(from dateTime: some DateTime, at offset: ZoneOffset) -> Instant

  /// Computes the local date/time for the *UTC* instant adjusted by `offset`.
  ///
  /// - Parameters:
  ///   - instant: The UTC instant to compute the local date/time for.
  ///   - offset:  The fixed offset associated with the instant.
  /// - Returns: The local date/time for the given instant.
  ///
  func localDateTime(instant: Instant, at offset: ZoneOffset) -> LocalDateTime

  /// Computes the date (year, month, day) for the *UTC* instant adjusted by `offset`.
  ///
  /// - Parameters:
  ///   - instant: The UTC instant.
  ///   - offset:  The fixed offset associated with the instant.
  /// - Returns: The (year, month, day) in the proleptic Gregorian calendar.
  ///
  func localDate(instant: Instant, at offset: ZoneOffset) -> LocalDate

  /// Determines the valid range of values for the specified component at a given instant.
  ///
  /// - Parameters:
  ///   - component: The component to determine the range for.
  ///   - instant: The instant to determine the valid range at.
  /// - Returns: A range of valid values for the specified component at the given instant.
  ///
  func range<C>(
    of component: C,
    at instant: Instant
  ) -> Range<C.Value> where C: IntegerDateTimeComponentKind, C.Value: SignedInteger

  func adding<C>(
    components addition: some ComponentContainer,
    to original: C,
    resolution: ResolutionStrategy
  ) throws -> C where C: ComponentContainer & ComponentBuildable
}

extension CalendarSystem {

  /// Converts the given `Instant` to a set of components in the specified time zone.
  ///
  /// - Parameters:
  ///   - instant: The instant to convert.
  ///   - zone: The time zone of instant.
  /// - Returns: A set of components representing the instant in the specified time zone.
  /// - Throws: An error if the conversion fails or the components are invalid.
  ///
  public func components<C>(
    from instant: Instant,
    in zone: Zone
  ) throws -> C where C: ComponentBuildable {
    return try components(from: instant, in: zone, as: C.self)
  }

  public func adding<C>(
    components addition: some ComponentContainer,
    to original: C
  ) throws -> C where C: ComponentContainer & ComponentBuildable {
    return try adding(components: addition, to: original, resolution: .default)
  }

}

extension CalendarSystem where Self == GregorianCalendarSystem {

  public static var `default`: Self {
    return .system
  }

}

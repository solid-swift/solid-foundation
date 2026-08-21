//
//  InstantSource.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/26/25.
//

/// Any source of ``Instant`` values on a documented time scale.
///
/// Sources used for calendar time must produce instants relative to Tempo's epoch.
/// Sources intended for interval measurement may use a source-specific epoch.
public protocol InstantSource: Sendable {

  /// Returns the current instant on this source's time scale.
  var instant: Instant { get }
}

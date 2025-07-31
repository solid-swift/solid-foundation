//
//  Digester.swift
//  SolidIO
//
//  Created by Kevin Wooten on 7/5/25.
//

import Foundation


/// Data digest computation.
///
public protocol Digester {

  /// Update the computed digest with the provided data.
  ///
  /// - Parameter data: Data to be included in the digest
  ///
  mutating func update(data: some DataProtocol)
  /// Finalizes, and returns, the computed digest.
  ///
  /// - Returns Computed digest.
  ///
  func finalize() -> Data
}

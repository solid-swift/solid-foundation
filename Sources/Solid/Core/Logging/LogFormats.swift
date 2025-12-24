//
//  LogFormats.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/29/25.
//

import Foundation


private let logLocale = Locale(identifier: "en_US_POSIX")


package enum ConstantFormatStyles {

  static func `for`<F: BinaryFloatingPoint>(_ type: F.Type) -> FloatingPointFormatStyle<F> {
    FloatingPointFormatStyle<F>()
      .notation(.automatic)
      .locale(logLocale)
      .grouping(.never)
      .sign(strategy: .always(includingZero: false))
  }

  static func `for`<I: BinaryInteger>(_ type: I.Type) -> IntegerFormatStyle<I> {
    IntegerFormatStyle<I>()
      .notation(.automatic)
      .locale(logLocale)
      .grouping(.never)
      .sign(strategy: .always(includingZero: false))
  }

}

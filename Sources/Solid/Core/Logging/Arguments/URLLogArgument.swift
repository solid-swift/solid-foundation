//
//  URLLogArgument.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/29/25.
//

import Foundation


public struct URLLogArgument: LogArgument {

  public let url: @Sendable () -> URL
  public let privacy: LogPrivacy

  public init(url: @Sendable @escaping () -> URL, privacy: LogPrivacy) {
    self.url = url
    self.privacy = privacy
  }

  public var constantValue: String {
    url().absoluteString
  }

  public var formattedValue: String {
    constantValue
  }

}


extension LogMessage.Interpolation {

  public mutating func append(_ argument: @autoclosure @escaping @Sendable () -> URL, privacy: LogPrivacy) {
    appendArgument(URLLogArgument(url: argument, privacy: privacy))
  }

}

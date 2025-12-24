//
//  LogPrivacyReportable.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/28/25.
//


public protocol LogPrivacyReportable: Sendable {

  static var logPrivacy: LogPrivacy { get }

}

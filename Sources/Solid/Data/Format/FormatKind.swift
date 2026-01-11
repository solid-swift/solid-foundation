//
//  FormatKind.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/10/26.
//


public enum FormatKind: String, CaseIterable, Sendable {
  case text
  case binary
}

extension FormatKind: Equatable {}
extension FormatKind: Hashable {}
extension FormatKind: Codable {}

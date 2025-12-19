//
//  TypeID.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/23/25.
//

import Foundation


public struct TypeID: Equatable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {

  public let type: Any.Type

  public init(_ type: Any.Type) {
    self.type = type
  }

  public var name: String { typeName(type) }
  public var uniqueName: String { typeName(type, includeModule: true) }

  public var description: String { name }
  public var debugDescription: String { "\(uniqueName)" }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.type == rhs.type
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(type))
  }

}


public func typeID(_ type: Any.Type) -> TypeID { .init(type) }

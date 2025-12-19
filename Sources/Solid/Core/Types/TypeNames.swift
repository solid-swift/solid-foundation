//
//  TypeNames.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/23/25.
//


public func typeName(_ type: Any.Type, includeModule: Bool = false) -> String {
  if includeModule {
    String(reflecting: type)
  } else {
    String(describing: type)
  }
}

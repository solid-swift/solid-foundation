//
//  LogFactory.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/28/25.
//

import Foundation


public enum LogFactory: Sendable {

  public enum Category {
    public enum BundleSource {
      case main
      case module
    }
    case bundle(BundleSource)
    case name(String)
  }

  public static func `for`(category: Category = .bundle(.module), type: Any.Type) -> Log {
    let typeName = String(describing: type)
    let name =
      if let lastDot = typeName.lastIndex(of: ".") {
        String(typeName[lastDot...])
      } else {
        typeName
      }
    return Self.for(category: category.fullName, name: name)
  }

  public static func `for`(category: Category = .bundle(.module), name: String) -> Log {
    return Self.for(category: category.fullName, name: name)
  }

}


extension LogFactory.Category {

  public var fullName: String {
    switch self {
    case .bundle(let bundleSource):
      let bundle: Bundle? =
        switch bundleSource {
        case .main: Bundle.main
        case .module:
          #if canImport(Foundation.Bundle.module)
            Bundle.module
          #else
            Bundle.main
          #endif
        }
      guard let bundle else {
        fatalError("Could not locate bundle for `\(bundleSource)`")
      }
      return bundle.bundleIdentifier ?? bundle.bundleURL.deletingPathExtension().lastPathComponent
    case .name(let name):
      return name
    }
  }

}

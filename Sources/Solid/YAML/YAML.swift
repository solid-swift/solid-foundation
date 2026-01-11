//
//  YAML.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData

public enum YAMLValueError: Error {
  case unsupported
}

public struct YAMLValueReader {

  public init(data: Data) {}

  public func readValue() throws -> Value {
    throw YAMLValueError.unsupported
  }
}

public struct YAMLValueWriter {

  public init() {}

  public func writeValue(_ value: Value) throws {
    throw YAMLValueError.unsupported
  }

  public func data() -> Data { Data() }
}

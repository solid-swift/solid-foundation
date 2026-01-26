//
//  ValueStyle.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

/// Presentation hints for streaming value events.
public enum ValueStyle: Sendable, Equatable {
  case scalar(ValueScalarStyle)
  case collection(ValueCollectionStyle)
}

/// Preferred rendering style for scalar values.
public enum ValueScalarStyle: Sendable, Equatable {
  case plain
  case singleQuoted
  case doubleQuoted
  case literal
  case folded
}

/// Preferred rendering style for collections.
public enum ValueCollectionStyle: Sendable, Equatable {
  case block
  case flow
}

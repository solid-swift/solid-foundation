//
//  Endian.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/8/25.
//


public protocol Endian: Sendable {
  @inlinable
  static func apply<I>(_ value: I) -> I where I: FixedWidthInteger
}

public enum LittleEndian: Endian {
  @inlinable
  public static func apply<I>(_ value: I) -> I where I: FixedWidthInteger {
    I(littleEndian: value)
  }
}

public enum BigEndian: Endian {
  @inlinable
  public static func apply<I>(_ value: I) -> I where I: FixedWidthInteger {
    I(bigEndian: value)
  }
}

public enum IdentityEndian: Endian {
  @inlinable
  public static func apply<I>(_ value: I) -> I where I: FixedWidthInteger {
    value
  }
}

extension Endian where Self == LittleEndian {
  public static var littleEndian: Self.Type { Self.self }
}

extension Endian where Self == BigEndian {
  public static var bigEndian: Self.Type { Self.self }
}

extension Endian where Self == IdentityEndian {
  public static var anyEndian: Self.Type { Self.self }
}

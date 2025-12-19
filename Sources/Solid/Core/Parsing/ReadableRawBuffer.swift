//
//  ReadableRawBuffer.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/6/25.
//


public struct ReadableRawBuffer<BufferEndian> where BufferEndian: Endian {

  public typealias Buffer = UnsafeRawBufferPointer
  public typealias Integer = FixedWidthInteger & Sendable

  public enum Error: Swift.Error {
    case offsetOutOfBounds
    case overflowOfResizedRange
    case integerhHasNoneBooleanValue
  }

  public internal(set) var source: Buffer.SubSequence

  @usableFromInline
  internal var sourceReadIndex: Index
  @usableFromInline
  internal var sourceStartIndex: Index { Index(source.startIndex) }
  @usableFromInline
  internal var sourceEndIndex: Index { Index(source.endIndex) }

  @inlinable
  public var readIndex: Index { sourceReadIndex }

  public var count: Int { source.count }
  public var isEmpty: Bool { source.isEmpty }

  @usableFromInline
  internal init<R>(
    _ source: Buffer,
    subrange: R,
  ) where R: RangeExpression, R.Bound == Buffer.Index {
    let selectedSubrange = source[subrange]
    self.source = selectedSubrange
    self.sourceReadIndex = Index(selectedSubrange.startIndex)
  }

  @inlinable
  public var remaining: Self {
    Self(source.base, subrange: readIndex.rawValue..<endIndex.rawValue)
  }

  @usableFromInline
  internal func validate(index: Index) throws {
    guard index >= sourceReadIndex && index < sourceEndIndex else {
      throw Error.offsetOutOfBounds
    }
  }

  @usableFromInline
  internal func validate(range: Range<Index>) throws {
    guard range.lowerBound >= sourceReadIndex && range.upperBound <= sourceEndIndex else {
      throw Error.offsetOutOfBounds
    }
  }

  @usableFromInline
  internal func resizeInt<S, D>(
    _ value: S,
    to dstType: D.Type = D.self
  ) throws -> D where S: Integer, D: Integer {
    guard let resized = D(exactly: value) else {
      throw Error.overflowOfResizedRange
    }
    return resized
  }

  @inlinable
  public func peekInt<I>(_ type: I.Type, at index: Index) throws -> I where I: Integer {
    try validate(range: index..<self.index(index, offsetBy: MemoryLayout<I>.size))
    let readOffset = distance(from: sourceStartIndex, to: index)
    let raw = source.loadUnaligned(fromByteOffset: readOffset, as: I.self)
    return BufferEndian.apply(raw)
  }

  @inlinable
  public func peekInt<S, D>(
    _ srcType: S.Type,
    as dstTYpe: D.Type = D.self,
    at index: Index
  ) throws -> D where S: Integer, D: Integer {
    let value = try peekInt(srcType, at: index)
    guard let resized = D(exactly: value) else {
      throw Error.overflowOfResizedRange
    }
    return resized
  }

  @inlinable
  public func peekBytes(count: Int, offsetBy offset: Int) throws -> some Collection<UInt8> {
    let offsetReadIndex = index(readIndex, offsetBy: offset)
    let range = offsetReadIndex..<self.index(offsetReadIndex, offsetBy: count)
    try validate(range: range)
    return source[range.lowerBound.rawValue..<range.upperBound.rawValue]
  }

  @inlinable
  public func peekBytes(count: Int) throws -> some Collection<UInt8> {
    return try peekBytes(count: count, offsetBy: 0)
  }

  @inlinable
  public mutating func readBytes(count: Int) throws -> some Collection<UInt8> {
    let bytes = try peekBytes(count: count)
    formIndex(&sourceReadIndex, offsetBy: count)
    return bytes
  }

  @inlinable
  public mutating func readInt<I>(_ type: I.Type) throws -> I where I: Integer {
    let value = try peekInt(type, at: readIndex)
    formIndex(&sourceReadIndex, offsetBy: MemoryLayout<I>.size)
    return value
  }

  @inlinable
  public mutating func readInt<S, D>(
    _ srcType: S.Type,
    as dstType: D.Type = D.self,
  ) throws -> D where S: Integer, D: Integer {
    let value = try peekInt(srcType, at: readIndex)
    guard let resized = D(exactly: value) else {
      throw Error.integerhHasNoneBooleanValue
    }
    formIndex(&sourceReadIndex, offsetBy: MemoryLayout<S>.size)
    return resized
  }

  public struct BoolEncoding<I>: Sendable where I: Integer {
    public let `true`: I
    public let `false`: I

    public static func `as`(_ rep: (`true`: I, `false`: I)) -> BoolEncoding<I> {
      Self(true: rep.true, false: rep.false)
    }

    public static func `as`(`true`: I, `false`: I) -> BoolEncoding<I> {
      Self(true: `true`, false: `false`)
    }

    public static var `default`: Self { .as((1, 0)) }
  }

  @usableFromInline
  internal func decode<I>(_ value: I, encoding: BoolEncoding<I>) throws -> Bool where I: Integer {
    // Validate the stored "boolean" was one of the true/false values
    guard value == encoding.false || value == encoding.true else {
      throw Error.integerhHasNoneBooleanValue
    }
    return value == encoding.true
  }

  @inlinable
  public mutating func readBool<I>(
    _ type: I.Type,
    encoding: BoolEncoding<I> = .default
  ) throws -> Bool where I: Integer {
    let intBool = try readInt(type)
    return try decode(intBool, encoding: encoding)
  }

  public mutating func readBuffer(count: Int) throws -> Self {
    let subrange = readIndex..<index(readIndex, offsetBy: count)
    try validate(range: subrange)
    formIndex(&sourceReadIndex, offsetBy: count)
    return ReadableRawBuffer(source.base, subrange: subrange.lowerBound.rawValue..<subrange.upperBound.rawValue)
  }

  public mutating func readBuffer<SubBufferEndian>(
    count: Int,
    endian: SubBufferEndian.Type
  ) throws -> ReadableRawBuffer<SubBufferEndian> where SubBufferEndian: Endian {
    let subrange = readIndex..<index(readIndex, offsetBy: count)
    try validate(range: subrange)
    formIndex(&sourceReadIndex, offsetBy: count)
    return ReadableRawBuffer<SubBufferEndian>(
      source.base,
      subrange: subrange.lowerBound.rawValue..<subrange.upperBound.rawValue
    )
  }

  @inlinable
  public mutating func skip(_ count: Int) throws {
    precondition(count > 0)
    let readIndex = index(readIndex, offsetBy: count)
    try validate(index: readIndex)
    self.sourceReadIndex = readIndex
  }

}

extension ReadableRawBuffer: Sequence {

  public typealias Iterator = Buffer.SubSequence.Iterator

  public func makeIterator() -> Iterator {
    source.makeIterator()
  }

}

extension ReadableRawBuffer: Collection, BidirectionalCollection {

  public struct Index: RawRepresentable, Strideable {

    public typealias RawValue = Int
    public typealias Stride = Int

    public var rawValue: Int

    @inlinable
    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    @inlinable
    public init(_ rawValue: Int) {
      self.rawValue = rawValue
    }

    @inlinable
    public static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.rawValue < rhs.rawValue
    }

    public func distance(to other: Self) -> Int {
      other.rawValue - rawValue
    }

    public func advanced(by n: Int) -> Self {
      Self(rawValue + n)
    }
  }

  public var startIndex: Index { readIndex }
  public var endIndex: Index { Index(source.endIndex) }

  public func index(before i: Index) -> Index {
    Index(source.index(before: i.rawValue))
  }

  public func index(after i: Index) -> Index {
    Index(source.index(after: i.rawValue))
  }

  public func index(_ i: Index, offsetBy distance: Int) -> Index {
    Index(source.index(i.rawValue, offsetBy: distance))
  }

  public subscript(position: Index) -> UInt8 {
    source[position.rawValue]
  }

  public subscript<R>(bounds: R) -> ReadableRawBuffer<BufferEndian> where R: RangeExpression, R.Bound == Index {
    let subrange = bounds.relative(to: self)
    return Self(source.base, subrange: subrange.lowerBound.rawValue..<subrange.upperBound.rawValue)
  }

}

extension ReadableRawBuffer: CustomStringConvertible {

  public var description: String {
    "\(Self.self)(count: \(count), readIndex: \(readIndex.rawValue))"
  }

}

extension ReadableRawBuffer where BufferEndian == BigEndian {

  public init(_ source: Buffer) {
    self.init(source, subrange: source.startIndex...)
  }

  public static func bigEndian<R>(
    _ source: Buffer,
    subrange: R
  ) -> ReadableRawBuffer<BigEndian> where R: RangeExpression, R.Bound == Int {
    ReadableRawBuffer<BigEndian>(source, subrange: subrange)
  }

}

extension ReadableRawBuffer where BufferEndian == LittleEndian {

  public static func littleEndian<R>(
    _ source: Buffer,
    subrange: R
  ) -> ReadableRawBuffer<LittleEndian> where R: RangeExpression, R.Bound == Int {
    ReadableRawBuffer<LittleEndian>(source, subrange: subrange)
  }

}

extension ReadableRawBuffer.Index: CustomStringConvertible {

  public var description: String {
    "\(Self.self)(\(rawValue))"
  }

}

extension ReadableRawBuffer.Index: ExpressibleByIntegerLiteral {

  public init(integerLiteral value: IntegerLiteralType) {
    self.rawValue = Int(value)
  }
}

//
//  ContentEncodingTypes.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/11/25.
//

import SolidCore
import SolidData
import Foundation


public final class ContentEncodingTypes: ContentEncodingLocator, @unchecked Sendable {

  public enum Error: Swift.Error {

    public enum EncodeReason: Sendable {
      case invalidValue
    }

    public enum DecodeReason: Sendable {
      case invalidData
    }

    case notFound(String)
    case decodeError(reason: DecodeReason, encoding: String)
    case encodeError(reason: EncodeReason, encoding: String)
  }

  private static let log = LogFactory.for(type: ContentMediaTypeTypes.self)

  public private(set) var contentEncodings: [String: Schema.ContentEncodingType] = [:]
  private let lock = ReadersWriterLock()

  public init() {
    // Register the default encodings
    register(contentEncoding: Base16.instance)
    register(contentEncoding: Base32.instance)
    register(contentEncoding: Base32Hex.instance)
    register(contentEncoding: Base64.instance)
    register(contentEncoding: Base64Url.instance)
    register(contentEncoding: MimeQuotedPrintable.instance)
  }

  public func locate(contentEncoding id: String) throws -> Schema.ContentEncodingType {
    try lock.withReadLock {
      guard let contentType = contentEncodings[id] else {
        throw Error.notFound(id)
      }
      return contentType
    }
  }

  public func register(contentEncoding: Schema.ContentEncodingType) {
    lock.withWriteLock {
      if contentEncodings.updateValue(contentEncoding, forKey: contentEncoding.identifier) != nil {
        Self.log.warning("Duplicate content encoding registered: \(contentEncoding.identifier)")
      }
    }
  }

}

extension ContentEncodingTypes {

  public enum Base64: Schema.ContentEncodingType {
    case instance

    public var identifier: String { "base64" }

    public func encode(_ value: Value) throws -> String {
      guard case .bytes(let bytes) = value else {
        throw Error.encodeError(reason: .invalidValue, encoding: identifier)
      }
      return bytes.baseEncoded(using: .base64)
    }

    public func decode(_ string: String) throws -> Value {
      guard let data = Data(baseEncodedString: string, encoding: .base64) else {
        throw Error.decodeError(reason: .invalidData, encoding: string)
      }
      return .bytes(data)
    }
  }

  public enum Base64Url: Schema.ContentEncodingType {
    case instance

    public var identifier: String { "base64url" }

    public func encode(_ value: Value) throws -> String {
      guard case .bytes(let bytes) = value else {
        throw Error.encodeError(reason: .invalidValue, encoding: identifier)
      }
      return bytes.baseEncoded(using: .base64Url)
    }

    public func decode(_ string: String) throws -> Value {
      guard let data = Data(baseEncodedString: string, encoding: .base64Url) else {
        throw Error.decodeError(reason: .invalidData, encoding: string)
      }
      return .bytes(data)
    }
  }

  public enum Base32: Schema.ContentEncodingType {
    case instance

    public var identifier: String { "base32" }

    public func encode(_ value: Value) throws -> String {
      guard case .bytes(let bytes) = value else {
        throw Error.encodeError(reason: .invalidValue, encoding: identifier)
      }
      return bytes.baseEncoded(using: .base32)
    }

    public func decode(_ string: String) throws -> Value {
      guard let data = Data(baseEncodedString: string, encoding: .base32) else {
        throw Error.decodeError(reason: .invalidData, encoding: string)
      }
      return .bytes(data)
    }
  }

  public enum Base32Hex: Schema.ContentEncodingType {
    case instance

    public var identifier: String { "base32hex" }

    public func encode(_ value: Value) throws -> String {
      guard case .bytes(let bytes) = value else {
        throw Error.encodeError(reason: .invalidValue, encoding: identifier)
      }
      return bytes.baseEncoded(using: .base32Hex)
    }

    public func decode(_ string: String) throws -> Value {
      guard let data = Data(baseEncodedString: string, encoding: .base32Hex) else {
        throw Error.decodeError(reason: .invalidData, encoding: string)
      }
      return .bytes(data)
    }
  }

  public enum Base16: Schema.ContentEncodingType {
    case instance

    public var identifier: String { "base16" }

    public func encode(_ value: Value) throws -> String {
      guard case .bytes(let bytes) = value else {
        throw Error.encodeError(reason: .invalidValue, encoding: identifier)
      }
      return bytes.baseEncoded(using: .base16)
    }

    public func decode(_ string: String) throws -> Value {
      guard let data = Data(baseEncodedString: string, encoding: .base16) else {
        throw Error.decodeError(reason: .invalidData, encoding: string)
      }
      return .bytes(data)
    }
  }

  public enum MimeQuotedPrintable: Schema.ContentEncodingType {
    case instance

    public var identifier: String { "quoted-printable" }

    public func encode(_ value: Value) throws -> String {
      guard case .bytes(let bytes) = value else {
        throw Error.encodeError(reason: .invalidValue, encoding: identifier)
      }
      return bytes.mimeQuotedPrintableEncoded()
    }

    public func decode(_ string: String) throws -> Value {
      guard let data = Data(mimeQuotedPrintableEncodedString: string) else {
        throw Error.decodeError(reason: .invalidData, encoding: string)
      }
      return .bytes(data)
    }
  }

}

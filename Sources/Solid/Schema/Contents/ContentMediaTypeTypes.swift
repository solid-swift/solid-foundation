//
//  ContentMediaTypeTypes.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/9/25.
//

import SolidCore


public final class ContentMediaTypeTypes: ContentMediaTypeLocator, @unchecked Sendable {

  public enum Error: Swift.Error {
    case notFound(String)
  }

  private static let log = LogFactory.for(type: ContentMediaTypeTypes.self)

  public private(set) var contentMediaTypes: [String: Schema.ContentMediaTypeType] = [:]
  private let lock = ReadersWriterLock()

  public init() {
    // Register the default content types
    register(contentMediaType: JSONContentMediaTypeType())
  }

  public func locate(contentMediaType id: String) throws -> Schema.ContentMediaTypeType {
    try lock.withReadLock {
      guard let contentMediaType = contentMediaTypes[id] else {
        throw Error.notFound(id)
      }
      return contentMediaType
    }
  }

  public func register(contentMediaType: Schema.ContentMediaTypeType) {
    lock.withWriteLock {
      if contentMediaTypes.updateValue(contentMediaType, forKey: contentMediaType.identifier) != nil {
        Self.log.warning("Duplicate content media-type registered: \(contentMediaType.identifier)")
      }
    }
  }

}

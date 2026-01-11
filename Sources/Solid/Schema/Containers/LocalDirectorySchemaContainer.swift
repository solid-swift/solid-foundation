//
//  LocalDirectorySchemaContainer.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/16/25.
//

import SolidURI
import SolidJSON
import Foundation


public final class LocalDirectorySchemaContainer: SchemaLocator {

  public let directory: URI
  private nonisolated(unsafe) var cache: [URI: Schema] = [:]
  private let lock = NSLock()
  private let caching: Bool

  public init(for uri: URI, caching: Bool = true) {
    self.directory = uri.removing(.fragment, .query).directoryPath()
    self.cache = [:]
    self.caching = caching
  }

  public convenience init?(for url: URL, caching: Bool = true) {
    guard let uri = url.uri else {
      return nil
    }
    self.init(for: uri, caching: caching)
  }

  public func locate(schemaId id: URI, options: Schema.Options) throws -> Schema? {

    let resourceId = id.removing(.query, .fragment)
    let relativeResourceId = resourceId.relative()
    let fileLoc = relativeResourceId.resolved(against: directory)

    guard fileLoc.scheme == "file" else {
      return nil
    }

    if caching, let cached = lock.withLock({ cache[fileLoc] ?? cache[resourceId] }) {
      return cached
    }

    do {

      let data = try Data(contentsOf: fileLoc.url)
      let value = try JSONValueReader(data: data).read()

      let resourceSchema = try Schema.Builder.build(from: value, resourceId: resourceId, options: options)

      if caching {
        lock.withLock {
          cache[fileLoc] = resourceSchema
        }
      }

      return resourceSchema

    } catch {
      if error is URLError || error is CocoaError {
        return nil
      }
      throw error
    }
  }
}

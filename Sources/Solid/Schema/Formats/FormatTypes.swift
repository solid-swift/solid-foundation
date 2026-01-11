//
//  FormatTypes.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/9/25.
//

import SolidCore
import SolidData
import SolidID
import SolidNet
import SolidURI
import SolidTempo
import Foundation


/// Local format type registry.
///
public class FormatTypes: FormatTypeLocator, @unchecked Sendable {

  /// Errors related to format types.
  public enum Error: Swift.Error {

    /// The format type is unknown.
    case unknownFormat(String)
  }

  private var formats: [String: Schema.FormatType] = [:]
  private let lock = ReadersWriterLock()

  /// Initializes the type registry with the default format types.
  ///
  /// - Note: This initializer registers the default format types.
  ///
  public init() {
    // Register the draft 2020-12 formats
    register(format: DateTimeFormatType.instance)
    register(format: DateFormatType.instance)
    register(format: TimeFormatType.instance)
    register(format: DurationFormatType.instance)
    register(format: EmailFormatType.instance)
    register(format: IDNEmailFormatType.instance)
    register(format: HostnameFormatType.instance)
    register(format: IDNHostnameFormatType.instance)
    register(format: IPv4FormatType.instance)
    register(format: IPv6FormatType.instance)
    register(format: URIFormatType.instance)
    register(format: URIReferenceFormatType.instance)
    register(format: IRIFormatType.instance)
    register(format: IRIReferenceFormatType.instance)
    register(format: UUIDFormatType.instance)
    register(format: URITemplateFormatType.instance)
    register(format: JSONPointerFormatType.instance)
    register(format: RelativeJSONPointerFormatType.instance)
    register(format: RegexFormatType.instance)
  }

  /// Locates a format by type identifier.
  ///
  /// - Parameter id: The identifier of the format type to locate.
  /// - Returns: The format type associated with the identifier.
  /// - Throws: An error if the format type is unknown.
  ///
  public func locate(formatType id: String) throws -> Schema.FormatType {
    lock.withReadLock {
      guard let format = formats[id] else {
        return UnknownFormatType.instance
      }
      return format
    }
  }

  /// Registers a format type.
  ///
  /// - Parameter format: The format type to register.
  ///
  public func register(format: Schema.FormatType) {
    lock.withWriteLock {
      formats[format.identifier] = format
    }
  }

}

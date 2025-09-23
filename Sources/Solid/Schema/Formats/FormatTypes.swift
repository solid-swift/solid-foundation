//
//  FormatTypes.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/9/25.
//

import SolidData
import SolidURI
import SolidNet
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
  private let lock = NSLock()

  /// Initializes the type registry with the default format types.
  ///
  /// - Note: This initializer registers the default format types.
  ///
  public init() {
    // Register the draft 2020-12 formats
    register(format: FormatTypes.DateTimeType.instance)
    register(format: FormatTypes.DateType.instance)
    register(format: FormatTypes.TimeType.instance)
    register(format: FormatTypes.DurationType.instance)
    register(format: FormatTypes.EmailType.instance)
    register(format: FormatTypes.IDNEmailType.instance)
    register(format: FormatTypes.HostnameType.instance)
    register(format: FormatTypes.IDNHostnameType.instance)
    register(format: FormatTypes.Ipv4Type.instance)
    register(format: FormatTypes.Ipv6Type.instance)
    register(format: FormatTypes.URIType.instance)
    register(format: FormatTypes.URIReferenceType.instance)
    register(format: FormatTypes.IRIType.instance)
    register(format: FormatTypes.IRIReferenceType.instance)
    register(format: FormatTypes.UUIDType.instance)
    register(format: FormatTypes.URITemplateType.instance)
    register(format: FormatTypes.JSONPointerType.instance)
    register(format: FormatTypes.RelativeJSONPointerType.instance)
    register(format: FormatTypes.RegexType.instance)
  }

  /// Locates a format by type identifier.
  ///
  /// - Parameter id: The identifier of the format type to locate.
  /// - Returns: The format type associated with the identifier.
  /// - Throws: An error if the format type is unknown.
  ///
  public func locate(formatType id: String) throws -> Schema.FormatType {
    lock.withLock {
      guard let format = formats[id] else {
        return UnknownType.instance
      }
      return format
    }
  }

  /// Registers a format type.
  ///
  /// - Parameter format: The format type to register.
  ///
  public func register(format: Schema.FormatType) {
    lock.withLock {
      formats[format.identifier] = format
    }
  }

}

extension FormatTypes {

  public enum UnknownType: Schema.FormatType {
    case instance

    public var identifier: String { "" }

    public func validate(_ value: Value) -> Bool {
      return true
    }

    public func convert(_ value: Value) -> Value? {
      return nil
    }
  }

  /// RFC 3339 date-time format type.
  public enum DateTimeType: Schema.FormatType {
    case instance

    public var identifier: String { "date-time" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let string) = value else {
        return true    // Non-string values are valid
      }
      return OffsetDateTime.parse(string: string) != nil
    }

    public func convert(_ value: Value) -> Value? {
      guard case .string(let string) = value else {
        return nil
      }
      guard let value = OffsetDateTime.parse(string: string) else {
        return nil
      }
      return nil
    }
  }

  /// RFC 3339 date format type.
  public enum DateType: Schema.FormatType {
    case instance

    public static let formatStyle = Foundation.Date.FormatStyle()
      .year(.padded(4))
      .month(.twoDigits)
      .day(.twoDigits)
      .locale(.init(identifier: "en_US"))

    public var identifier: String { "date" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let string) = value else {
        return false
      }
      return LocalDate.parse(string: string) != nil
    }
  }

  /// RFC 3339 time format type.
  public enum TimeType: Schema.FormatType {
    case instance

    public static let formatStyle = Foundation.Date.FormatStyle()
      .hour(.twoDigits(amPM: .omitted))
      .minute(.twoDigits)
      .second(.twoDigits)
      .secondFraction(.fractional(9))
      .timeZone(.iso8601(.short))
      .locale(.init(identifier: "en_US"))

    public var identifier: String { "time" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let string) = value else {
        return false
      }
      return OffsetTime.parse(string: string) != nil
    }
  }

  /// RFC 3339 duration format type.
  public enum DurationType: Schema.FormatType {
    case instance

    public var identifier: String { "duration" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let value) = value else {
        return false
      }
      return PeriodDuration.parse(string: value) != nil
    }
  }

  /// RFC 5321 email format type.
  public enum EmailType: Schema.FormatType {
    case instance

    public var identifier: String { "email" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let value) = value else {
        return false
      }
      return EmailAddress.parse(string: value) != nil
    }
  }

  /// RFC 6531 IDN email format type.
  public enum IDNEmailType: Schema.FormatType {
    case instance

    public var identifier: String { "idn-email" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let value) = value else {
        return false
      }
      return IDNEmailAddress.parse(string: value) != nil
    }
  }

  /// RFC 1123 hostname format type.
  public enum HostnameType: Schema.FormatType {
    case instance

    public var identifier: String { "hostname" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let string) = value else {
        return false
      }
      return Hostname.parse(string: string) != nil
    }
  }

  /// RFC 5890 IDN hostname format type.
  public enum IDNHostnameType: Schema.FormatType {
    case instance

    public var identifier: String { "idn-hostname" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let string) = value else {
        return false
      }
      return IDNHostname.parse(string: string) != nil
    }
  }

  /// RFC 2673 IPv4 address format type.
  public enum Ipv4Type: Schema.FormatType {
    case instance

    public var identifier: String { "ipv4" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let string) = value else {
        return false
      }
      return IPv4Address.parse(string: string) != nil
    }
  }

  /// RFC 4291 IPv6 address format type.
  public enum Ipv6Type: Schema.FormatType {
    case instance

    public var identifier: String { "ipv6" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let string) = value else {
        return false
      }
      return IPv6Address.parse(string: string) != nil
    }
  }

  /// RFC 3986 URI format type.
  public enum URIType: Schema.FormatType {
    case instance

    public var identifier: String { "uri" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let string) = value else {
        return false
      }
      return URI(encoded: string, requirements: .uri) != nil
    }
  }

  /// RFC 3986 URI reference format type.
  public enum URIReferenceType: Schema.FormatType {
    case instance

    public var identifier: String { "uri-reference" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let string) = value else {
        return false
      }
      let uri = URI(encoded: string, requirements: .uriReference)
      return uri != nil
    }
  }

  /// RFC 3987 IRI format type.
  public enum IRIType: Schema.FormatType {
    case instance

    public var identifier: String { "iri" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let string) = value else {
        return false
      }
      return URI(encoded: string, requirements: .iri) != nil
    }
  }

  /// RFC 3987 IRI reference format type.
  public enum IRIReferenceType: Schema.FormatType {
    case instance

    public var identifier: String { "iri-reference" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let string) = value else {
        return false
      }
      return URI(encoded: string, requirements: .iriReference) != nil
    }
  }

  /// UUID format type.
  public enum UUIDType: Schema.FormatType {
    case instance

    public var identifier: String { "uuid" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let string) = value else {
        return false
      }
      return UUID(uuidString: string) != nil
    }
  }

  /// RFC 6570 URI template format type.
  public enum URITemplateType: Schema.FormatType {
    case instance

    public var identifier: String { "uri-template" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let string) = value else {
        return false
      }
      do {
        _ = try URI.Template(string)
        return true
      } catch {
        return false
      }
    }
  }

  /// JSON Pointer format type.
  public enum JSONPointerType: Schema.FormatType {
    case instance

    public var identifier: String { "json-pointer" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let string) = value else {
        return false
      }
      return Pointer(encoded: string) != nil
    }
  }

  /// Relative JSON Pointer format type.
  public enum RelativeJSONPointerType: Schema.FormatType {
    case instance

    public var identifier: String { "relative-json-pointer" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let string) = value else {
        return false
      }
      return RelativePointer(encoded: string) != nil
    }
  }

  /// Regular expression format type.
  public enum RegexType: Schema.FormatType {
    case instance

    public var identifier: String { "regex" }

    public func validate(_ value: Value) -> Bool {
      guard case .string(let string) = value else {
        return false
      }
      do {
        _ = try Regex(string)
        return true
      } catch {
        return false
      }
    }
  }

}

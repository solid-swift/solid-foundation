//
//  MediaType-Constants-Documents.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/28/26.
//

public extension MediaType {

  /// `text/plain`.
  static let plainText = MediaType(type: .text, subtype: "plain")
  /// `text/html`.
  static let html = MediaType(type: .text, subtype: "html")
  /// `text/css`.
  static let css = MediaType(type: .text, subtype: "css")
  /// `text/csv`.
  static let csv = MediaType(type: .text, subtype: "csv")
  /// `text/markdown`.
  static let markdown = MediaType(type: .text, subtype: "markdown")
  /// `text/javascript`.
  static let javascript = MediaType(type: .text, subtype: "javascript")
  /// `text/calendar`.
  static let calendar = MediaType(type: .text, subtype: "calendar")
  /// `text/vcard`.
  static let vcard = MediaType(type: .text, subtype: "vcard")
  /// `application/rtf`.
  static let rtf = MediaType(type: .application, subtype: "rtf")
  /// `application/pdf`.
  static let pdf = MediaType(type: .application, subtype: "pdf")
  /// `application/epub+zip`.
  static let epub = MediaType(type: .application, subtype: "epub", suffix: "zip")
  /// `application/postscript`.
  static let postscript = MediaType(type: .application, subtype: "postscript")
  /// `application/msword`.
  static let doc = MediaType(type: .application, subtype: "msword")
  /// `application/vnd.openxmlformats-officedocument.wordprocessingml.document`.
  static let docx = MediaType(
    type: .application,
    tree: .vendor,
    subtype: "openxmlformats-officedocument.wordprocessingml.document"
  )
  /// `application/vnd.ms-excel`.
  static let xls = MediaType(type: .application, tree: .vendor, subtype: "ms-excel")
  /// `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`.
  static let xlsx = MediaType(
    type: .application,
    tree: .vendor,
    subtype: "openxmlformats-officedocument.spreadsheetml.sheet"
  )
  /// `application/vnd.ms-powerpoint`.
  static let ppt = MediaType(type: .application, tree: .vendor, subtype: "ms-powerpoint")
  /// `application/vnd.openxmlformats-officedocument.presentationml.presentation`.
  static let pptx = MediaType(
    type: .application,
    tree: .vendor,
    subtype: "openxmlformats-officedocument.presentationml.presentation"
  )
  /// `application/vnd.oasis.opendocument.text`.
  static let odt = MediaType(type: .application, tree: .vendor, subtype: "oasis.opendocument.text")
  /// `application/vnd.oasis.opendocument.spreadsheet`.
  static let ods = MediaType(type: .application, tree: .vendor, subtype: "oasis.opendocument.spreadsheet")
  /// `application/vnd.oasis.opendocument.presentation`.
  static let odp = MediaType(type: .application, tree: .vendor, subtype: "oasis.opendocument.presentation")
  /// `application/zip`.
  static let zip = MediaType(type: .application, subtype: "zip")
  /// `application/gzip`.
  static let gzip = MediaType(type: .application, subtype: "gzip")
  /// `application/x-tar`.
  static let tar = MediaType(type: .application, tree: .obsolete, subtype: "tar")
  /// `application/x-brotli`.
  static let brotli = MediaType(type: .application, tree: .obsolete, subtype: "brotli")
  /// `application/zstd`.
  static let zstandard = MediaType(type: .application, subtype: "zstd")
  /// `application/x-7z-compressed`.
  static let sevenZip = MediaType(type: .application, tree: .obsolete, subtype: "7z-compressed")
  /// `application/vnd.rar`.
  static let rar = MediaType(type: .application, tree: .vendor, subtype: "rar")
  /// `application/octet-stream`.
  static let octetStream = MediaType(type: .application, subtype: "octet-stream")
}

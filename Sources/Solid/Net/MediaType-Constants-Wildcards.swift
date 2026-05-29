//
//  MediaType-Constants-Wildcards.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/28/26.
//

public extension MediaType {

  /// `*/*`.
  static let any = MediaType(type: .any, subtype: "*")
  /// `text/*`.
  static let anyText = MediaType(type: .text, subtype: "*")
  /// `image/*`.
  static let anyImage = MediaType(type: .image, subtype: "*")
  /// `audio/*`.
  static let anyAudio = MediaType(type: .audio, subtype: "*")
  /// `video/*`.
  static let anyVideo = MediaType(type: .video, subtype: "*")
  /// `font/*`.
  static let anyFont = MediaType(type: .font, subtype: "*")
  /// `model/*`.
  static let anyModel = MediaType(type: .model, subtype: "*")
  /// `multipart/*`.
  static let anyMultipart = MediaType(type: .multipart, subtype: "*")
  /// `*/*+json`.
  static let anyJSON = MediaType(type: .any, subtype: "*", suffix: "json")
  /// `*/*+xml`.
  static let anyXML = MediaType(type: .any, subtype: "*", suffix: "xml")
  /// `*/*+cbor`.
  static let anyCBOR = MediaType(type: .any, subtype: "*", suffix: "cbor")
  /// `*/*+cbor-seq`.
  static let anyCBORSequence = MediaType(type: .any, subtype: "*", suffix: "cbor-seq")
}

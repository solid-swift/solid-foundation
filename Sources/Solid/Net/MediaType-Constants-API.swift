//
//  MediaType-Constants-API.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/28/26.
//

public extension MediaType {

  /// `application/json`.
  static let json = MediaType(type: .application, subtype: "json")
  /// `application/cbor`.
  static let cbor = MediaType(type: .application, subtype: "cbor")
  /// `application/cbor-seq`.
  static let cborSequence = MediaType(type: .application, subtype: "cbor-seq")
  /// `application/xml`.
  static let xml = MediaType(type: .application, subtype: "xml")
  /// `application/yaml`.
  static let yaml = MediaType(type: .application, subtype: "yaml")
  /// `application/x-ndjson`.
  static let ndjson = MediaType(type: .application, tree: .obsolete, subtype: "ndjson")
  /// `application/json-seq`.
  static let jsonSequence = MediaType(type: .application, subtype: "json-seq")
  /// `application/json-patch+json`.
  static let jsonPatch = MediaType(type: .application, subtype: "json-patch", suffix: "json")
  /// `application/merge-patch+json`.
  static let mergePatchJSON = MediaType(type: .application, subtype: "merge-patch", suffix: "json")
  /// `text/event-stream`.
  static let eventStream = MediaType(type: .text, subtype: "event-stream")
  /// `application/x-www-form-urlencoded`.
  static let formUrlEncoded = MediaType(type: .application, tree: .obsolete, subtype: "www-form-urlencoded")
  /// `multipart/form-data`.
  static let multipartFormData = MediaType(type: .multipart, subtype: "form-data")
  /// `multipart/mixed`.
  static let multipartMixed = MediaType(type: .multipart, subtype: "mixed")
  /// `multipart/alternative`.
  static let multipartAlternative = MediaType(type: .multipart, subtype: "alternative")
  /// `multipart/related`.
  static let multipartRelated = MediaType(type: .multipart, subtype: "related")
  /// `application/graphql`.
  static let graphql = MediaType(type: .application, subtype: "graphql")
  /// `application/graphql-response+json`.
  static let graphqlResponseJSON = MediaType(type: .application, subtype: "graphql-response", suffix: "json")
  /// `application/activity+json`.
  static let activityJSON = MediaType(type: .application, subtype: "activity", suffix: "json")
  /// `application/hal+json`.
  static let halJSON = MediaType(type: .application, subtype: "hal", suffix: "json")
  /// `application/vnd.api+json`.
  static let jsonAPI = MediaType(type: .application, tree: .vendor, subtype: "api", suffix: "json")
  /// `application/ld+json`.
  static let jsonLD = MediaType(type: .application, subtype: "ld", suffix: "json")
  /// `application/manifest+json`.
  static let webAppManifest = MediaType(type: .application, subtype: "manifest", suffix: "json")
  /// `application/atom+xml`.
  static let atom = MediaType(type: .application, subtype: "atom", suffix: "xml")
  /// `application/rss+xml`.
  static let rss = MediaType(type: .application, subtype: "rss", suffix: "xml")
  /// `application/msgpack`.
  static let messagePack = MediaType(type: .application, subtype: "msgpack")
  /// `application/protobuf`.
  static let protobuf = MediaType(type: .application, subtype: "protobuf")
  /// `application/avro`.
  static let avro = MediaType(type: .application, subtype: "avro")
  /// `application/vnd.apache.parquet`.
  static let parquet = MediaType(type: .application, tree: .vendor, subtype: "apache.parquet")
  /// `application/wasm`.
  static let wasm = MediaType(type: .application, subtype: "wasm")
  /// `application/senml+cbor`.
  static let senmlCBOR = MediaType(type: .application, subtype: "senml", suffix: "cbor")
  /// `application/sensml+cbor`.
  static let sensmlCBOR = MediaType(type: .application, subtype: "sensml", suffix: "cbor")
  /// `application/senml-etch+cbor`.
  static let senmlEtchCBOR = MediaType(type: .application, subtype: "senml-etch", suffix: "cbor")
}


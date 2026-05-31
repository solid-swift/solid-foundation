//
//  MediaType-Constants-Security.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/28/26.
//

public extension MediaType {

  /// `application/problem+json`.
  static let problemJSON = MediaType(type: .application, subtype: "problem", suffix: "json")
  /// `application/problem+xml`.
  static let problemXML = MediaType(type: .application, subtype: "problem", suffix: "xml")
  /// `application/concise-problem-details+cbor`.
  static let conciseProblemCBOR = MediaType(type: .application, subtype: "concise-problem-details", suffix: "cbor")
  /// `application/jose`.
  static let jose = MediaType(type: .application, subtype: "jose")
  /// `application/jose+json`.
  static let joseJSON = MediaType(type: .application, subtype: "jose", suffix: "json")
  /// `application/jwt`.
  static let jwt = MediaType(type: .application, subtype: "jwt")
  /// `application/jwk+json`.
  static let jwkJSON = MediaType(type: .application, subtype: "jwk", suffix: "json")
  /// `application/jwk-set+json`.
  static let jwkSetJSON = MediaType(type: .application, subtype: "jwk-set", suffix: "json")
  /// `application/cms`.
  static let cms = MediaType(type: .application, subtype: "cms")
  /// `application/cose`.
  static let cose = MediaType(type: .application, subtype: "cose")
  /// `application/cose-key`.
  static let coseKey = MediaType(type: .application, subtype: "cose-key")
  /// `application/cose-key-set`.
  static let coseKeySet = MediaType(type: .application, subtype: "cose-key-set")
  /// `application/cose-x509`.
  static let coseX509 = MediaType(type: .application, subtype: "cose-x509")
  /// `application/cwt`.
  static let cwt = MediaType(type: .application, subtype: "cwt")
  /// `application/pem-certificate-chain`.
  static let pemCertificateChain = MediaType(type: .application, subtype: "pem-certificate-chain")
  /// `application/pkix-cert`.
  static let pkixCertificate = MediaType(type: .application, subtype: "pkix-cert")
  /// `application/pkix-attr-cert`.
  static let pkixAttributeCertificate = MediaType(type: .application, subtype: "pkix-attr-cert")
  /// `application/pkix-crl`.
  static let pkixCertificateRevocationList = MediaType(type: .application, subtype: "pkix-crl")
  /// `application/pkix-pkipath`.
  static let pkixCertificationPath = MediaType(type: .application, subtype: "pkix-pkipath")
  /// `application/pkcs7-mime`.
  static let pkcs7Mime = MediaType(type: .application, subtype: "pkcs7-mime")
  /// `application/pkcs7-signature`.
  static let pkcs7Signature = MediaType(type: .application, subtype: "pkcs7-signature")
  /// `application/pkcs10`.
  static let pkcs10 = MediaType(type: .application, subtype: "pkcs10")
  /// `application/pkcs8`.
  static let pkcs8 = MediaType(type: .application, subtype: "pkcs8")
  /// `application/pkcs8-encrypted`.
  static let pkcs8Encrypted = MediaType(type: .application, subtype: "pkcs8-encrypted")
  /// `application/pkcs12`.
  static let pkcs12 = MediaType(type: .application, subtype: "pkcs12")
  /// `application/pgp-keys`.
  static let pgpKeys = MediaType(type: .application, subtype: "pgp-keys")
  /// `application/pgp-signature`.
  static let pgpSignature = MediaType(type: .application, subtype: "pgp-signature")
  /// `application/pgp-encrypted`.
  static let pgpEncrypted = MediaType(type: .application, subtype: "pgp-encrypted")
  /// `application/x-x509-ca-cert`.
  static let x509CACertificate = MediaType(type: .application, tree: .obsolete, subtype: "x509-ca-cert")
  /// `application/x-x509-user-cert`.
  static let x509UserCertificate = MediaType(type: .application, tree: .obsolete, subtype: "x509-user-cert")
}


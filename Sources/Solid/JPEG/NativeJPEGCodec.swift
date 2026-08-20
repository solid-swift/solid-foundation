enum NativeJPEGCodec {

  static func encode(samples: [UInt8], options: JPEGEncodingOptions) throws -> [UInt8] {
    throw JPEGError.unsupportedFeature("native encoder is not installed")
  }

  static func decode(bytes: [UInt8], options: JPEGDecodingOptions) throws -> JPEGDecodingResult {
    throw JPEGError.unsupportedFeature("native decoder is not installed")
  }

}

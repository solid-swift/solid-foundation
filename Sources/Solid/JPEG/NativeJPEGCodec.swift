enum NativeJPEGCodec {

  static func encode(samples: [UInt8], options: JPEGEncodingOptions) throws -> [UInt8] {
    try NativeJPEGEncoder.encode(samples: samples, options: options)
  }

  static func decode(bytes: [UInt8], options: JPEGDecodingOptions) throws -> JPEGDecodingResult {
    try NativeJPEGDecoder.decode(bytes: bytes, options: options)
  }

}

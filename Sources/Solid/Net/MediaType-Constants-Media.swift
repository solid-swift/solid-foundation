//
//  MediaType-Constants-Media.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/28/26.
//

public extension MediaType {

  /// `image/apng`.
  static let apng = MediaType(type: .image, subtype: "apng")
  /// `image/png`.
  static let png = MediaType(type: .image, subtype: "png")
  /// `image/jpeg`.
  static let jpeg = MediaType(type: .image, subtype: "jpeg")
  /// `image/gif`.
  static let gif = MediaType(type: .image, subtype: "gif")
  /// `image/bmp`.
  static let bmp = MediaType(type: .image, subtype: "bmp")
  /// `image/webp`.
  static let webp = MediaType(type: .image, subtype: "webp")
  /// `image/avif`.
  static let avif = MediaType(type: .image, subtype: "avif")
  /// `image/heic`.
  static let heic = MediaType(type: .image, subtype: "heic")
  /// `image/heif`.
  static let heif = MediaType(type: .image, subtype: "heif")
  /// `image/jp2`.
  static let jpeg2000 = MediaType(type: .image, subtype: "jp2")
  /// `image/jxl`.
  static let jpegXL = MediaType(type: .image, subtype: "jxl")
  /// `image/svg+xml`.
  static let svg = MediaType(type: .image, subtype: "svg", suffix: "xml")
  /// `image/tiff`.
  static let tiff = MediaType(type: .image, subtype: "tiff")
  /// `image/vnd.microsoft.icon`.
  static let icon = MediaType(type: .image, tree: .vendor, subtype: "microsoft.icon")
  /// `image/x-icon`.
  static let xIcon = MediaType(type: .image, tree: .obsolete, subtype: "icon")
  /// `audio/aac`.
  static let aac = MediaType(type: .audio, subtype: "aac")
  /// `audio/flac`.
  static let flac = MediaType(type: .audio, subtype: "flac")
  /// `audio/midi`.
  static let midi = MediaType(type: .audio, subtype: "midi")
  /// `audio/mpeg`.
  static let mp3 = MediaType(type: .audio, subtype: "mpeg")
  /// `audio/mp4`.
  static let mp4Audio = MediaType(type: .audio, subtype: "mp4")
  /// `audio/mpeg`.
  static let mpegAudio = MediaType(type: .audio, subtype: "mpeg")
  /// `audio/ogg`.
  static let oggAudio = MediaType(type: .audio, subtype: "ogg")
  /// `audio/opus`.
  static let opus = MediaType(type: .audio, subtype: "opus")
  /// `audio/wav`.
  static let wav = MediaType(type: .audio, subtype: "wav")
  /// `audio/webm`.
  static let webmAudio = MediaType(type: .audio, subtype: "webm")
  /// `audio/3gpp`.
  static let audio3GPP = MediaType(type: .audio, subtype: "3gpp")
  /// `audio/3gpp2`.
  static let audio3GPP2 = MediaType(type: .audio, subtype: "3gpp2")
  /// `video/mp4`.
  static let mp4 = MediaType(type: .video, subtype: "mp4")
  /// `video/mpeg`.
  static let mpegVideo = MediaType(type: .video, subtype: "mpeg")
  /// `video/quicktime`.
  static let quickTime = MediaType(type: .video, subtype: "quicktime")
  /// `video/webm`.
  static let webmVideo = MediaType(type: .video, subtype: "webm")
  /// `video/x-msvideo`.
  static let avi = MediaType(type: .video, tree: .obsolete, subtype: "msvideo")
  /// `video/3gpp`.
  static let video3GPP = MediaType(type: .video, subtype: "3gpp")
  /// `video/3gpp2`.
  static let video3GPP2 = MediaType(type: .video, subtype: "3gpp2")
  /// `video/av1`.
  static let av1 = MediaType(type: .video, subtype: "av1")
  /// `video/h264`.
  static let h264 = MediaType(type: .video, subtype: "h264")
  /// `video/h265`.
  static let h265 = MediaType(type: .video, subtype: "h265")
  /// `video/hevc`.
  static let hevc = MediaType(type: .video, subtype: "hevc")
  /// `video/x-matroska`.
  static let matroska = MediaType(type: .video, tree: .obsolete, subtype: "matroska")
  /// `video/x-m4v`.
  static let m4v = MediaType(type: .video, tree: .obsolete, subtype: "m4v")
  /// `video/mp2t`.
  static let mp2t = MediaType(type: .video, subtype: "mp2t")
  /// `video/ogg`.
  static let oggVideo = MediaType(type: .video, subtype: "ogg")
  /// `font/collection`.
  static let collectionFont = MediaType(type: .font, subtype: "collection")
  /// `font/otf`.
  static let otf = MediaType(type: .font, subtype: "otf")
  /// `font/ttf`.
  static let ttf = MediaType(type: .font, subtype: "ttf")
  /// `font/woff`.
  static let woff = MediaType(type: .font, subtype: "woff")
  /// `font/woff2`.
  static let woff2 = MediaType(type: .font, subtype: "woff2")
  /// `model/gltf+json`.
  static let gltfJSON = MediaType(type: .model, subtype: "gltf", suffix: "json")
  /// `model/gltf-binary`.
  static let gltfBinary = MediaType(type: .model, subtype: "gltf-binary")
  /// `model/stl`.
  static let stl = MediaType(type: .model, subtype: "stl")
  /// `model/obj`.
  static let obj = MediaType(type: .model, subtype: "obj")
}

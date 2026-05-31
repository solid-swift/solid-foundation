// snippet.hide
//
//  SolidHTTPExample.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/28/26.
//

// snippet.show
import Solid

// snippet.hide
func solidHTTPExample() throws {
  // snippet.show
  var fields = HTTPFields()
  fields.setContentType(.json)
  fields.setAccept(.json)

  let accepted = try fields.acceptMediaRanges()
  let selected = accepted.bestMatch(in: [MediaType.problemJSON, .cbor])
  // snippet.hide
  print(selected ?? .octetStream)
}
// snippet.show

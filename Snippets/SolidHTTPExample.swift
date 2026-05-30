//
//  SolidHTTPExample.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/28/26.
//

import Solid


func solidHTTPExample() throws {
  var fields = HTTPFields()
  fields.setContentType(.json)
  fields.setAccept(.json)

  let accepted = try fields.acceptMediaRanges()
  let selected = accepted.bestMatch(in: [MediaType.problemJSON, .cbor])
  print(selected ?? .octetStream)
}

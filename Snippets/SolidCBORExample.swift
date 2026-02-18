import SolidCBOR
import SolidData

// snippet.hide
func cborExample() throws {
  // snippet.show
  // Encode to CBOR
  let value: Value = ["temperature": 23.5, "humidity": 65]
  let output = try CBORValueWriter.write(value)

  // Decode from CBOR
  var reader = CBORValueReader(data: output)
  let decoded = try reader.read()
  // snippet.hide
  _ = decoded
}
// snippet.show

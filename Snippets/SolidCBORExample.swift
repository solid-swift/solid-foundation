import SolidCBOR
import SolidData

// snippet.hide
func cborExample() throws {
  // snippet.show
  // Encode to CBOR
  let value: Value = ["temperature": 23.5, "humidity": 65]
  let output = try CBORWriter.write(value)

  // Decode from CBOR
  let reader = CBORReader(data: output)
  let decoded = try reader.read()
  // snippet.hide
  _ = decoded
}
// snippet.show

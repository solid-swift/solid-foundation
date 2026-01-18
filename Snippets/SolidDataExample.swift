import SolidData
import SolidNumeric

// snippet.hide
func dataExample() {
  // snippet.show
  // Values work like you'd expect
  let user: Value = [
      "name": "Alice",
      "age": 30,
      "active": true,
      "tags": ["admin", "verified"]
  ]

  // Access nested data
  if let name = user[.string("name")]?.string {
      print("Hello, \(name)")
  }

  // Numbers preserve precision
  let precise: Value = .number(BigDecimal("123.456789012345678901234567890"))
  // snippet.hide
  _ = precise
}
// snippet.show

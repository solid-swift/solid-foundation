import SolidJSON
import SolidData
import Foundation

// snippet.hide
func jsonExample() throws {
  // snippet.show
  // Parse JSON to Value
  let json = """
  {"name": "Bob", "scores": [95, 87, 92]}
  """
  let reader = JSONValueReader(string: json)
  let value = try reader.read()

  // Write Value to JSON
  let output = JSONValueWriter.write(value)
  // snippet.hide
  _ = output
}
// snippet.show

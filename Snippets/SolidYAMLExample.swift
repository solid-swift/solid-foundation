import SolidYAML
import SolidData
import Foundation

// snippet.hide
func yamlExample() throws {
  // snippet.show
  // Parse YAML to Value
  let yaml = """
  name: Casey
  scores:
    - 95
    - 87
    - 92
  """
  var reader = YAMLValueReader(string: yaml)
  let value = try reader.read()

  // Write Value to YAML
  let output = try YAMLValueWriter.write(value)
  // snippet.hide
  _ = output
}
// snippet.show

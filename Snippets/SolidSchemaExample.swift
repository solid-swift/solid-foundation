import SolidSchema
import SolidData

// snippet.hide
func schemaExample() throws {
  // snippet.show
  // Build a schema
  let schema = Schema.Builder.build(constant: [
      "type": "object",
      "properties": [
          "name": ["type": "string", "minLength": 1],
          "age": ["type": "integer", "minimum": 0],
          "email": ["type": "string", "format": "email"]
      ],
      "required": ["name", "email"]
  ])

  // Validate data
  let userData: Value = [
      "name": "Alice",
      "age": 30,
      "email": "alice@example.com"
  ]

  let result = try schema.validate(instance: userData)
  if result.isValid {
      print("Data is valid!")
  }
  // snippet.hide
}
// snippet.show

import SolidIO

// snippet.hide
func ioExample() async throws {
  // snippet.show
  // Read a file asynchronously
  let source = try FileSource(path: "/path/to/file.txt")
  for try await chunk in source.buffers() {
      // Process each chunk
      _ = chunk
  }

  // Pipe data between streams
  let input = try FileSource(path: "/path/to/input.txt")
  let output = try FileSink(path: "/path/to/output.txt")
  try await input.pipe(to: output)
  // snippet.hide
}
// snippet.show

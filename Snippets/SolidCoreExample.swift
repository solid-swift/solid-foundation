import SolidCore
import Foundation

// snippet.hide
func coreExample() {
  // snippet.show
  // Base encodings for all your encoding needs
  let data = "Hello, World!".data(using: .utf8)!
  let base64 = BaseEncoding.base64.encode(data: data)
  let base32 = BaseEncoding.base32.encode(data: data)

  // Thread-safe logging with privacy controls
  let log = LogFactory.for(name: "MyApp")
  log.info("Application started")
  log.debug("Processing data...")
  // snippet.hide
  _ = (base64, base32)
}
// snippet.show

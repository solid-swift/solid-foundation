import SolidNet

// snippet.hide
func netExample() {
  // snippet.show
  // Parse and validate email addresses
  if let email = EmailAddress.parse(string: "user@example.com") {
      print("Local: \(email.local)")   // "user"
      print("Domain: \(email.domain)") // "example.com"
  }

  // Hostnames with IDN support
  let hostname = IDNHostname.parse(string: "münchen.example.com")

  // IP addresses
  let ipv4 = IPv4Address.parse(string: "192.168.1.1")
  let ipv6 = IPv6Address.parse(string: "2001:db8::1")
  // snippet.hide
  _ = (hostname, ipv4, ipv6)
}
// snippet.show

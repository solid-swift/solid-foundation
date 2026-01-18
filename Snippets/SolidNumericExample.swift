import SolidNumeric

// snippet.hide
func numericExample() {
  // snippet.show
  // Arbitrary-precision integers
  let bigNumber: BigInt = 123456789012345678901234567890
  let doubled = bigNumber * 2
  let factorial = (1...100).reduce(BigInt.one) { $0 * BigInt($1) }

  // Arbitrary-precision decimals for when Float64 isn't precise enough
  let price = BigDecimal("19.99")
  let taxRate = BigDecimal("0.0825")
  let total = price * (BigDecimal.one + taxRate)
  print(total.rounded(places: 2)) // 21.64
  // snippet.hide
  _ = (doubled, factorial)
}
// snippet.show

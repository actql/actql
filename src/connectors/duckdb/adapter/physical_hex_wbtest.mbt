///|
test "physical float hex words preserve exact bits and strict syntax" {
  for
    (text, expected) in [
      ("00000000", 0UL),
      ("80000000", 2147483648UL),
      ("ffffffff", 4294967295UL),
      ("0000000000000001", 1UL),
      ("0010000000000000", 4503599627370496UL),
      ("3ff0000000000000", 4607182418800017408UL),
      ("7fefffffffffffff", 9218868437227405311UL),
      ("8000000000000000", 9223372036854775808UL),
      ("ffffffffffffffff", 18446744073709551615UL),
    ] {
    assert_eq(hex_bits(text, text.length()), Some(expected))
  }
  for text in ["FFFFFFFF", "0000000g", "+0000000", " 0000000", "0000000\n"] {
    assert_eq(hex_bits(text, 8), None)
  }
  assert_eq(hex_bits("00000000", 16), None)
  // Nibble positions on both sides of the 32-bit word boundary are independent.
  for bit in 0..<64 {
    let digits = "0123456789abcdef"
    let text = StringBuilder()
    for position in 0..<16 {
      let nibble = if position == 15 - bit / 4 { 1 << (bit % 4) } else { 0 }
      text.write_char(digits[nibble].to_int().unsafe_to_char())
    }
    assert_eq(hex_bits(text.to_string(), 16), Some(1UL << bit))
  }
}

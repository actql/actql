///|
test "hex expression and named arguments produce the existing numeric literals" {
  for
    (text, value) in [
      ("0x0", 0.0),
      ("-0x0", 0.0),
      ("0X10", 16.0),
      ("-0x1F", -31.0),
      ("0x1fffffffffffff", 9007199254740991.0),
    ] {
    assert_eq(numeric_literal(text).unwrap(), value)
  }
  assert_eq(emit("-0x0"), "{\"literal\":0}")
  assert_eq(emit("0x10"), "{\"literal\":16}")
  assert_eq(emit("-0X1f"), "{\"literal\":-31}")
  for text in ["0x20000000000000", "-0x20000000000000"] {
    assert_true(numeric_literal(text) is Err(InvalidNumber), msg=text)
  }
}

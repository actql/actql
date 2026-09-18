///|
test "safe scalar constructors preserve admitted invariants" {
  assert_true(boolean_value(true) is Boolean(true))
  assert_true(number_value(1.5) is Some(Number(1.5)))
  assert_true(number_value(0.0) is Some(Number(0.0)))
  assert_true(number_value(-0.0) is None)
  assert_true(number_value(0.0 / 0.0) is None)
  assert_true(number_value(1.0 / 0.0) is None)
  assert_true(text_value("é", 2) is Some(Text("é")))
  assert_true(text_value("é", 1) is None)
  assert_true(text_value("e\u{0301}", 3) is None)
}

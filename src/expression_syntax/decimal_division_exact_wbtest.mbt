///|
test "exact division machine source retains all five fields and quantize exclusion" {
  let body = "{\"decimal_divide\":{\"left\":{\"field\":\"a\"},\"right\":{\"literal\":8},\"precision\":38,\"scale\":3,\"rounding\":\"exact\"}}"
  assert_tree(body, body)
  for
    invalid in [
      "{\"decimal_divide\":{\"left\":null,\"right\":8,\"scale\":3}}", "{\"quantize\":{\"value\":null,\"precision\":38,\"scale\":3,\"rounding\":\"exact\"}}",
    ] {
    assert_true(admit(source_cursor(invalid), test_limits()) is Err(_))
  }
}

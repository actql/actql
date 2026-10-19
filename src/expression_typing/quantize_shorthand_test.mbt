///|
test "public QUANTIZE shorthand keeps literal NULL context distinct from numeric promotion" {
  assert_type(
    "\"quantize(NULL,2)\"", "{}", "null", "{\"type\":\"decimal\",\"nullable\":true,\"precision\":38,\"scale\":2}",
  )
  assert_type(
    "\"quantize(NULL,38,2,'half_even')\"", "{}", "null", "{\"type\":\"decimal\",\"nullable\":true,\"precision\":38,\"scale\":2}",
  )
  assert_rejected("\"quantize(1,2)\"", "{}", "null", "TypeMismatch")
  assert_rejected("\"quantize('1',2)\"", "{}", "null", "TypeMismatch")
  assert_rejected(
    "\"quantize($i,2)\"", "{}", "{\"i\":{\"type\":\"int64\"}}", "TypeMismatch",
  )
  assert_rejected(
    "\"quantize(unknown_quantize_value,2)\"", "{}", "null", "UnknownField",
  )
  assert_rejected(
    "\"quantize($missing_quantize,2)\"", "{}", "null", "UnknownParameter",
  )
}

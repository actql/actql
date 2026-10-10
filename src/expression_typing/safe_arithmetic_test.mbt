///|
test "SAFE binary arithmetic always returns nullable Number and NEGATE preserves operand nullability" {
  for op in ["safe_add", "safe_subtract", "safe_multiply", "safe_divide"] {
    for args in ["1, 2", "NULL, 2", "1, NULL", "NULL, NULL"] {
      assert_type(
        "\"" + op + "(" + args + ")\"",
        "{}",
        "null",
        "{\"type\":\"number\",\"nullable\":true}",
      )
    }
  }
  assert_type(
    "\"safe_negate(1)\"", "{}", "null", "{\"type\":\"number\",\"nullable\":false}",
  )
  assert_type(
    "\"safe_negate(NULL)\"", "{}", "null", "{\"type\":\"number\",\"nullable\":true}",
  )
  assert_type(
    "\"safe_negate(n)\"", "{\"n\":{\"type\":\"number\",\"nullable\":true}}", "null",
    "{\"type\":\"number\",\"nullable\":true}",
  )
}

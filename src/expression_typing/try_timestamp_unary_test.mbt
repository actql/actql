///|
test "unary TRY_TIMESTAMP has exact conversion domains without pattern obligations" {
  let fields = "{\"s\":{\"type\":\"string\",\"nullable\":true},\"t\":{\"type\":\"timestamp\",\"nullable\":false}}"
  for
    child in [
      "s", "t", "NULL", "'bad'", "CAST('1970-01-01T00:00:00.000Z' AS TIMESTAMP)",
    ] {
    let source = "\"try_timestamp(" + child + ")\""
    assert_type(
      source, fields, "null", "{\"type\":\"timestamp\",\"nullable\":true}",
    )
    let checked = @expression_typing.check(
      syntax(source),
      env(fields~),
      test_limits(),
    ).unwrap()
    assert_eq(@expression_typing.pending_validations(checked).length(), 0)
  }
  let patterned = @expression_typing.check(
    syntax("\"try_timestamp(NULL,'yyyy')\""),
    env(),
    test_limits(),
  ).unwrap()
  assert_true(@expression_typing.pending_validations(patterned).length() > 0)
}

///|
test "unary TRY_TIMESTAMP never promotes other or unresolved domains" {
  for child in ["1", "TRUE", "CAST('1' AS DECIMAL(2,0))", "[1]"] {
    assert_rejected(
      "\"try_timestamp(" + child + ")\"",
      "{}",
      "null",
      "TypeMismatch",
    )
  }
  assert_rejected("\"try_timestamp([])\"", "{}", "null", "NullTypeUnresolved")
  assert_rejected("\"try_timestamp(missing)\"", "{}", "null", "UnknownField")
  assert_rejected(
    "\"try_timestamp($missing)\"", "{}", "null", "UnknownParameter",
  )
}

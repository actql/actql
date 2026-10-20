///|
test "TRY_NUMBER Number identity retains nullable output without String obligations" {
  let fields = "{\"n\":{\"type\":\"number\",\"nullable\":false},\"m\":{\"type\":\"number\",\"nullable\":true}}"
  for child in ["n", "m", "1", "1 / 0"] {
    let source = "\"try_number(" + child + ")\""
    assert_type(
      source, fields, "null", "{\"type\":\"number\",\"nullable\":true}",
    )
    let checked = @expression_typing.check(
      syntax(source),
      env(fields~),
      test_limits(),
    ).unwrap()
    assert_eq(@expression_typing.pending_validations(checked).length(), 0)
  }
  let string = @expression_typing.check(
    syntax("\"try_number('bad')\""),
    env(),
    test_limits(),
  ).unwrap()
  assert_true(@expression_typing.pending_validations(string).length() > 0)
}

///|
test "TRY_NUMBER identity does not admit other scalar or unknown domains" {
  let fields = "{\"b\":{\"type\":\"boolean\",\"nullable\":false},\"i\":{\"type\":\"int64\",\"nullable\":false},\"d\":{\"type\":\"decimal\",\"precision\":8,\"scale\":2,\"nullable\":false},\"t\":{\"type\":\"timestamp\",\"nullable\":false}}"
  for child in ["TRUE", "b", "i", "d", "t", "[1]"] {
    assert_rejected(
      "\"try_number(" + child + ")\"",
      fields,
      "null",
      "TypeMismatch",
    )
  }
}

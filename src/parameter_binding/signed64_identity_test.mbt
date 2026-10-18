///|
test "signed64 Parameters retain the exact original marker without Number Decimal or Text substitution" {
  let declaration = "{\"x\":{\"type\":\"int64\"}}"
  for
    text in [
      "-9223372036854775808", "9007199254740992", "9007199254740993", "9223372036854775807",
    ] {
    let bound = identity_ready(declaration, "{\"x\":\"" + text + "\"}")
    assert_eq(
      identity_text(bound),
      "{\"values\":{\"x\":{\"$actql_value\":[\"int64\",\"" +
      text +
      "\"]}},\"version\":\"actql-parameter-values/0.1\"}",
    )
  }
  let exact = identity_ready(declaration, "{\"x\":\"9007199254740993\"}")
  let adjacent = identity_ready(declaration, "{\"x\":\"9007199254740992\"}")
  let string = identity_ready(
    "{\"x\":{\"type\":\"string\"}}", "{\"x\":\"9007199254740993\"}",
  )
  assert_false(identity_cid(exact) == identity_cid(adjacent))
  assert_false(identity_cid(exact) == identity_cid(string))
  assert_true(bind(declaration, "{\"x\":9007199254740993}") is Err(_))
  assert_true(bind(declaration, "{\"x\":\"9223372036854775808\"}") is Err(_))
}

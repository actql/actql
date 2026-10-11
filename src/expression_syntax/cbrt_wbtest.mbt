///|
test "cbrt canonical unary bodies match text and reject argument arrays" {
  for
    (source, expected) in [
      ("cbrt(x)", "{\"cbrt\":{\"field\":\"x\"}}"),
      ("cbrt(NULL)", "{\"cbrt\":{\"literal\":null}}"),
      ("cbrt(cbrt(8))", "{\"cbrt\":{\"cbrt\":{\"literal\":8}}}"),
    ] {
    assert_tree("\"" + source + "\"", expected)
    assert_tree(expected, expected)
  }
  for
    body in [
      "[]", "[{\"literal\":8}]", "[{\"literal\":8},{\"literal\":2}]", "{\"value\":{\"literal\":8}}",
      "{}", "8", "null",
    ] {
    assert_true(
      admit(source_cursor("{\"cbrt\":" + body + "}"), test_limits()) is Err(_),
      msg=body,
    )
  }
  assert_true(
    admit(source_cursor("{\"CBRT\":{\"literal\":8}}"), test_limits()) is Err(_),
  )
}

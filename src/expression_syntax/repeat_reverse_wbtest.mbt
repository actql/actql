///|
test "repeat canonical Arguments and reverse unary Body remain distinct" {
  for
    (source, expected) in [
      ("repeat(s,n)", "{\"repeat\":[{\"field\":\"s\"},{\"field\":\"n\"}]}"),
      ("reverse(s)", "{\"reverse\":{\"field\":\"s\"}}"),
    ] {
    assert_tree("\"" + source + "\"", expected)
    assert_tree(expected, expected)
  }
  for
    body in [
      "[]", "[{\"literal\":\"a\"}]", "[{\"literal\":\"a\"},{\"literal\":2},{\"literal\":3}]",
      "{\"value\":{\"literal\":\"a\"},\"count\":{\"literal\":2}}", "{\"literal\":\"a\"}",
    ] {
    assert_true(
      admit(source_cursor("{\"repeat\":" + body + "}"), test_limits()) is Err(_),
      msg=body,
    )
  }
  for
    body in [
      "[]", "[{\"literal\":\"a\"}]", "{\"value\":{\"literal\":\"a\"}}", "{}",
    ] {
    assert_true(
      admit(source_cursor("{\"reverse\":" + body + "}"), test_limits())
      is Err(_),
      msg=body,
    )
  }
  for tag in ["REPEAT", "REVERSE"] {
    assert_true(
      admit(
        source_cursor("{\"" + tag + "\":{\"literal\":\"a\"}}"),
        test_limits(),
      )
      is Err(_),
    )
  }
}

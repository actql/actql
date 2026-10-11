///|
test "split admits one or two ordered String expressions" {
  for
    (source, expected) in [
      ("split('a,b')", "{\"split\":[{\"literal\":\"a,b\"}]}"),
      ("split(s,d)", "{\"split\":[{\"field\":\"s\"},{\"field\":\"d\"}]}"),
    ] {
    assert_tree("\"" + source + "\"", expected)
    assert_tree(expected, expected)
  }
  for
    body in [
      "[]", "[{\"literal\":\"a\"},{\"literal\":\",\"},{\"literal\":\"b\"}]", "{\"value\":{\"literal\":\"a\"}}",
    ] {
    assert_true(
      admit(source_cursor("{\"split\":" + body + "}"), test_limits()) is Err(_),
    )
  }
}

///|
test "canonical split admits ordered Arguments and rejects named Body shapes" {
  // These authored machine trees bypass text-call parsing so the grammar
  // cannot accidentally classify SPLIT with named-body SUBSTRING.
  for
    source in [
      "{\"split\":[{\"literal\":\"a,b\"}]}", "{\"split\":[{\"field\":\"input\"},{\"lower\":{\"$param\":\"delimiter\"}}]}",
    ] {
    assert_tree(source, source)
  }
  for
    body in [
      "{}", "{\"value\":{\"literal\":\"a,b\"}}", "{\"value\":{\"literal\":\"a,b\"},\"delimiter\":{\"literal\":\",\"}}",
      "{\"literal\":\"a,b\"}",
    ] {
    assert_true(
      admit(source_cursor("{\"split\":" + body + "}"), test_limits()) is Err(_),
      msg=body,
    )
  }
}

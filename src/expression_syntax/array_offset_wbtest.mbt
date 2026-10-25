///|
test "array offset common shapes are closed and retain both original children" {
  for op in ["array_offset", "array_safe_offset"] {
    let value = "{\"" +
      op +
      "\":{\"value\":{\"array\":[{\"literal\":7}]},\"index\":{\"literal\":0}}}"
    assert_tree(value, value)
    assert_tree("\"" + op + "([7], 0)\"", value)
    for
      body in [
        "{}", "{\"value\":{\"literal\":null}}", "{\"value\":{\"literal\":null},\"index\":{\"literal\":0},\"safe\":true}",
      ] {
      assert_true(
        admit(source_cursor("{\"" + op + "\":" + body + "}"), test_limits())
        is Err(_),
      )
    }
  }
}

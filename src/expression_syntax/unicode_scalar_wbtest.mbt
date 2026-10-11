///|
test "Unicode scalar canonical bodies are unary expressions not argument arrays" {
  for tag in ["byte_length", "unicode", "chr"] {
    let tree = "{\"" + tag + "\":{\"field\":\"value\"}}"
    assert_tree(tree, tree)
    assert_tree("\"" + tag + "(value)\"", tree)
    for body in ["[]", "[{\"literal\":1}]", "{\"value\":{\"literal\":1}}", "{}"] {
      assert_true(
        admit(source_cursor("{\"" + tag + "\":" + body + "}"), test_limits())
        is Err(_),
        msg=body,
      )
    }
  }
  assert_tree(
    "\"octet_length('😀')\"", "{\"byte_length\":{\"literal\":\"😀\"}}",
  )
  assert_true(
    admit(
      source_cursor("{\"octet_length\":{\"literal\":\"a\"}}"),
      test_limits(),
    )
    is Err(_),
  )
}

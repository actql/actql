///|
test "side slices and padding use closed ordered source arrays" {
  for tag in ["left", "right", "lpad", "rpad"] {
    let tree = "{\"" + tag + "\":[{\"literal\":\"abc\"},{\"literal\":2}]}"
    assert_tree(tree, tree)
    assert_tree("\"" + tag + "('abc',2)\"", tree)
    for
      body in [
        "[]", "[{\"literal\":\"abc\"}]", "[{\"literal\":\"abc\"},{\"literal\":2},{\"literal\":\"x\"},{\"literal\":\"y\"}]",
        "{\"value\":{\"literal\":\"abc\"},\"length\":{\"literal\":2}}",
      ] {
      assert_true(
        admit(source_cursor("{\"" + tag + "\":" + body + "}"), test_limits())
        is Err(_),
      )
    }
  }
  for tag in ["lpad", "rpad"] {
    let tree = "{\"" +
      tag +
      "\":[{\"literal\":\"abc\"},{\"literal\":2},{\"literal\":\"x\"}]}"
    assert_tree(tree, tree)
    assert_tree("\"" + tag + "('abc',2,'x')\"", tree)
  }
  for tag in ["left", "right"] {
    assert_true(
      admit(
        source_cursor(
          "{\"" +
          tag +
          "\":[{\"literal\":\"abc\"},{\"literal\":2},{\"literal\":\"x\"}]}",
        ),
        test_limits(),
      )
      is Err(_),
    )
  }
}

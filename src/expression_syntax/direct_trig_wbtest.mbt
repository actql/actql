///|
test "direct trig canonical unary bodies match text and refuse argument arrays" {
  for
    name in [
      "sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", "tanh", "asinh",
      "acosh", "atanh",
    ] {
    for
      (operand, child) in [
        ("x", "{\"field\":\"x\"}"),
        ("NULL", "{\"literal\":null}"),
        ("1 / 0", "{\"divide\":[{\"literal\":1},{\"literal\":0}]}"),
      ] {
      let expected = "{\"" + name + "\":" + child + "}"
      assert_tree("\"" + name + "(" + operand + ")\"", expected)
      assert_tree(expected, expected)
    }
    let nested = "{\"" + name + "\":{\"" + name + "\":{\"literal\":0.5}}}"
    assert_tree("\"" + name + "(" + name + "(0.5))\"", nested)
    assert_tree(nested, nested)
    for
      body in [
        "[]", "[{\"literal\":1}]", "[{\"literal\":1},{\"literal\":2}]", "{\"value\":{\"literal\":1}}",
        "{}", "1", "null",
      ] {
      assert_true(
        admit(source_cursor("{\"" + name + "\":" + body + "}"), test_limits())
        is Err(_),
        msg=name + ":" + body,
      )
    }
    for
      tag in [name.to_upper(), "safe_" + name, "SAFE." + name, "ACTQL." + name] {
      assert_true(
        admit(source_cursor("{\"" + tag + "\":{\"literal\":1}}"), test_limits())
        is Err(_),
      )
    }
  }
}

///|
test "atan2 canonical bodies are exactly two ordered expressions" {
  for
    (source, expected) in [
      ("atan2(x, $p)", "{\"atan2\":[{\"field\":\"x\"},{\"$param\":\"p\"}]}"),
      ("atan2($p, x)", "{\"atan2\":[{\"$param\":\"p\"},{\"field\":\"x\"}]}"),
      (
        "atan2(NULL, 1 / 0)", "{\"atan2\":[{\"literal\":null},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]}",
      ),
      (
        "atan2(atan2(1, 2), 3)", "{\"atan2\":[{\"atan2\":[{\"literal\":1},{\"literal\":2}]},{\"literal\":3}]}",
      ),
    ] {
    assert_tree("\"" + source + "\"", expected)
    assert_tree(expected, expected)
  }
  for
    body in [
      "[]", "[{\"literal\":1}]", "[{\"literal\":1},{\"literal\":2},{\"literal\":3}]",
      "{\"first\":{\"literal\":1},\"second\":{\"literal\":2}}", "{\"literal\":1}",
      "{}", "1", "null",
    ] {
    assert_true(
      admit(source_cursor("{\"atan2\":" + body + "}"), test_limits()) is Err(_),
      msg=body,
    )
  }
  for tag in ["ATAN2", "AtAn2", "safe_atan2", "SAFE.atan2", "ACTQL.atan2"] {
    assert_true(
      admit(
        source_cursor("{\"" + tag + "\":[{\"literal\":1},{\"literal\":2}]}"),
        test_limits(),
      )
      is Err(_),
    )
  }
}

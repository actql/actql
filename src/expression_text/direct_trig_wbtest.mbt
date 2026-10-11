///|
test "direct trig unary text calls preserve authored children without folding" {
  for
    name in [
      "sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", "tanh", "asinh",
      "acosh", "atanh",
    ] {
    for
      (operand, child) in [
        ("value", "{\"field\":\"value\"}"),
        ("$n", "{\"$param\":\"n\"}"),
        ("NULL", "{\"literal\":null}"),
        ("1 / 0", "{\"divide\":[{\"literal\":1},{\"literal\":0}]}"),
      ] {
      assert_tree(
        name + "(" + operand + ")",
        "{\"" + name + "\":" + child + "}",
      )
    }
    assert_tree(
      name + "(" + name + "(0.5))",
      "{\"" + name + "\":{\"" + name + "\":{\"literal\":0.5}}}",
    )
    for args in ["", "1,2", "1,2,3", "1,", "1e400"] {
      assert_true(parse(name + "(" + args + ")", test_limits()) is Err(_))
    }
    for
      spelling in [
        name.to_upper(),
        "\"" + name + "\"",
        "`" + name + "`",
        "safe_" + name,
        "SAFE." + name,
        "ACTQL." + name,
      ] {
      assert_true(parse(spelling + "(1)", test_limits()) is Err(_))
    }
  }
}

///|
test "atan2 text calls preserve first second order and require two operands" {
  for
    (source, expected) in [
      (
        "atan2(first, $second)", "{\"atan2\":[{\"field\":\"first\"},{\"$param\":\"second\"}]}",
      ),
      (
        "atan2($second, first)", "{\"atan2\":[{\"$param\":\"second\"},{\"field\":\"first\"}]}",
      ),
      (
        "atan2(NULL, 1 / 0)", "{\"atan2\":[{\"literal\":null},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]}",
      ),
      (
        "atan2(1 / 0, NULL)", "{\"atan2\":[{\"divide\":[{\"literal\":1},{\"literal\":0}]},{\"literal\":null}]}",
      ),
      (
        "atan2(atan2(1, 2), 3)", "{\"atan2\":[{\"atan2\":[{\"literal\":1},{\"literal\":2}]},{\"literal\":3}]}",
      ),
    ] {
    assert_tree(source, expected)
  }
  for args in ["", "1", "1,2,3", "1,", "1e400,0", "0,1e400"] {
    assert_true(parse("atan2(" + args + ")", test_limits()) is Err(_))
  }
  for
    spelling in [
      "ATAN2", "AtAn2", "\"atan2\"", "`atan2`", "safe_atan2", "SAFE.atan2", "ACTQL.atan2",
    ] {
    assert_true(parse(spelling + "(1,2)", test_limits()) is Err(_))
  }
}

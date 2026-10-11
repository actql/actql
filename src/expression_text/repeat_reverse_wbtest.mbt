///|
test "repeat binary and reverse unary text calls preserve ordered trees" {
  for
    (source, expected) in [
      (
        "repeat(value, count)", "{\"repeat\":[{\"field\":\"value\"},{\"field\":\"count\"}]}",
      ),
      ("reverse(value)", "{\"reverse\":{\"field\":\"value\"}}"),
      (
        "reverse(repeat('😀é',2))", "{\"reverse\":{\"repeat\":[{\"literal\":\"😀é\"},{\"literal\":2}]}}",
      ),
    ] {
    assert_tree(source, expected)
  }
  for args in ["", "'a'", "'a',2,3"] {
    assert_true(parse("repeat(" + args + ")", test_limits()) is Err(_))
  }
  for args in ["", "'a','b'"] {
    assert_true(parse("reverse(" + args + ")", test_limits()) is Err(_))
  }
}

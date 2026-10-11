///|
test "cbrt unary text calls preserve the authored child" {
  for
    (source, expected) in [
      ("cbrt(value)", "{\"cbrt\":{\"field\":\"value\"}}"),
      ("cbrt(NULL)", "{\"cbrt\":{\"literal\":null}}"),
      (
        "cbrt(1 / 0)", "{\"cbrt\":{\"divide\":[{\"literal\":1},{\"literal\":0}]}}",
      ),
      ("cbrt(cbrt(8))", "{\"cbrt\":{\"cbrt\":{\"literal\":8}}}"),
    ] {
    assert_tree(source, expected)
  }
  for args in ["", "1,2", "1,2,3"] {
    assert_true(parse("cbrt(" + args + ")", test_limits()) is Err(_))
  }
}

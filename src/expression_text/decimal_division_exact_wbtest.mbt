///|
test "exact division public text emits complete original children and target" {
  for scale in ["0", "3", "38"] {
    let expected = "{\"decimal_divide\":{\"left\":{\"$param\":\"a\"},\"right\":{\"field\":\"b\"},\"precision\":38,\"scale\":" +
      scale +
      ",\"rounding\":\"exact\"}}"
    assert_tree("decimal_divide($a,b,(" + scale + "))", expected)
    assert_tree("decimal_divide($a,b,38," + scale + ",'exact')", expected)
  }
  for
    source in [
      "decimal_divide(a,b)", "decimal_divide(a,b,38,2)", "decimal_divide(a,b,$s)",
      "decimal_divide(a,b,1+1)", "decimal_divide(a,b,'2')", "decimal_divide(a,b,-1)",
      "decimal_divide(a,b,39)", "decimal_divide(a,b,1.5)", "quantize(a,38,2,'exact')",
    ] {
    assert_true(parse(source, test_limits()) is Err(_))
  }
}

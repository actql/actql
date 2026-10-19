///|
test "public quantize shorthand text emits only the original complete body" {
  assert_tree(
    "quantize(amount,(2))", "{\"quantize\":{\"value\":{\"field\":\"amount\"},\"precision\":38,\"scale\":2,\"rounding\":\"half_even\"}}",
  )
  for scale in ["0", "38"] {
    assert_tree(
      "quantize($amount," + scale + ")",
      "{\"quantize\":{\"value\":{\"$param\":\"amount\"},\"precision\":38,\"scale\":" +
      scale +
      ",\"rounding\":\"half_even\"}}",
    )
  }
  assert_tree(
    "quantize(amount,8,2,'floor')", "{\"quantize\":{\"value\":{\"field\":\"amount\"},\"precision\":8,\"scale\":2,\"rounding\":\"floor\"}}",
  )
}

///|
test "public quantize shorthand text rejects dynamic malformed and partial targets" {
  for
    source in [
      "quantize(d)", "quantize(d,38,2)", "quantize(d,-1)", "quantize(d,39)", "quantize(d,1.5)",
      "quantize(d,$scale)", "quantize(d,1+1)", "quantize(d,'2')", "quantize(d,38,2,'nearest')",
    ] {
    assert_true(parse(source, test_limits()) is Err(_))
  }
}

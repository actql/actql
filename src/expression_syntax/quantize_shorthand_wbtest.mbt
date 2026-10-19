///|
test "quantize authoring defaults never admit a partial structured body" {
  for
    wire in [
      "{\"quantize\":{\"value\":{\"field\":\"d\"},\"scale\":2}}", "{\"quantize\":{\"value\":{\"field\":\"d\"},\"precision\":38,\"scale\":2}}",
    ] {
    assert_true(admit(source_cursor(wire), test_limits()) is Err(_))
  }
}

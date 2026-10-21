///|
test "unary Timestamp conversion is a closed choice distinct from an explicit pattern" {
  for
    wire in [
      "{\"try_timestamp\":{\"value\":{\"literal\":null}}}", "{\"try_timestamp\":{\"value\":{\"literal\":\"2000-02-29T00:00:00.123456789Z\"}}}",
    ] {
    assert_true(admit(source_cursor(wire), test_limits()) is Ok(_))
  }
  for
    wire in [
      "{\"try_timestamp\":{}}", "{\"try_timestamp\":{\"value\":{\"literal\":null},\"extra\":true}}",
      "{\"try_timestamp\":{\"value\":{\"literal\":null},\"pattern\":{\"literal\":null}}}",
    ] {
    assert_true(admit(source_cursor(wire), test_limits()) is Err(_))
  }
  // Syntax retains an authored String pattern for the existing typing and
  // profile validators; it must never rewrite that occurrence to unary.
  for
    (wire, expected) in [
      (
        "{\"try_timestamp\":{\"value\":{\"literal\":null},\"pattern\":{\"literal\":\"bad\"}}}",
        "{\"try_timestamp\":{\"pattern\":{\"literal\":\"bad\"},\"value\":{\"literal\":null}}}",
      ),
    ] {
    assert_eq(
      source_text(admit(source_cursor(wire), test_limits()).unwrap()),
      expected,
    )
  }
}

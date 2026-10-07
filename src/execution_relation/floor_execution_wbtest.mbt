///|
test "finite floor and ceiling use the common checked expression owner" {
  for
    (source, expected) in [
      ("{\"floor\":{\"literal\":2.3}}", 2.0),
      ("{\"floor\":{\"literal\":-2.3}}", -3.0),
      ("{\"floor\":{\"literal\":0.0}}", 0.0),
      (
        "{\"negate\":{\"floor\":{\"subtract\":[{\"literal\":0},{\"literal\":-2.3}]}}}",
        -2.0,
      ),
      (
        "{\"negate\":{\"floor\":{\"subtract\":[{\"literal\":0},{\"literal\":5e-324}]}}}",
        1.0,
      ),
    ] {
    let root = lowered(source)
    assert_true(
      evaluate_expression(root, Map([]), [], {
        remaining: 1000,
        max_frames: 100,
      })
      is Ok(Number(actual)) &&
      actual == expected,
    )
  }
}

///|
test "finite floor preserves SQL NULL and refuses other numeric domains" {
  assert_true(unary(@lower.Floor, Null) is Ok(Null))
  assert_true(unary(@lower.Floor, Number(-0.0)) is Ok(Number(0.0)))
  assert_true(unary(@lower.Floor, Boolean(true)) is Err(InvalidOperand))
  assert_true(unary(@lower.Floor, Text("2.3")) is Err(InvalidOperand))
  let decimal = @admitted.decimal_from_coefficient("23", 8, 1).unwrap()
  assert_true(unary(@lower.Floor, Captured(decimal)) is Err(InvalidOperand))
}

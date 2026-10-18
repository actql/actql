///|
test "signed64 captured comparison is exact and cannot enter existing arithmetic or mixed domains" {
  let left = capture(@admitted.signed64_value(9007199254740992L))
  let right = capture(@admitted.signed64_value(9007199254740993L))
  assert_true(binary(@lower.Equal, left, right) is Ok(Boolean(false)))
  assert_true(binary(@lower.Less, left, right) is Ok(Boolean(true)))
  assert_true(binary(@lower.Greater, right, left) is Ok(Boolean(true)))
  assert_true(binary(@lower.Equal, right, right) is Ok(Boolean(true)))
  for operation in [@lower.Add, @lower.Subtract, @lower.Multiply, @lower.Divide] {
    assert_true(binary(operation, right, left) is Err(InvalidOperand))
  }
  for
    other in [
      Number(9007199254740992.0),
      Text("9007199254740993"),
      capture(
        @admitted.decimal_from_coefficient("9007199254740993", 19, 0).unwrap(),
      ),
    ] {
    assert_true(binary(@lower.Equal, right, other) is Err(_))
  }
  assert_true(binary(@lower.Equal, right, Null) is Ok(Null))
}

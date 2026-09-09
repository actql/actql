///|
test "integer number preserves binary64 without pretending to narrow safely" {
  for
    value in [
      0.0, -0.0, 1.0, -1.0, 2147483648.0, 9007199254740991.0, 9007199254740992.0,
      -9007199254740992.0, 1.0e308,
    ] {
    let admitted = read_integer_number(value).unwrap()
    assert_eq(admitted.reinterpret_as_uint64(), value.reinterpret_as_uint64())
  }
  for value in [0.5, -0.5, 5.0e-324, 1.0 / 0.0, -1.0 / 0.0, 0.0 / 0.0] {
    assert_true(read_integer_number(value) is None)
  }
  assert_true(read_safe_integer(9007199254740992.0) is None)
  assert_true(read_safe_integer(1.0e308) is None)
  assert_eq(read_safe_integer(9007199254740991.0), Some(9007199254740991L))
}

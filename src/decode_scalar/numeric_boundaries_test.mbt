///|
test "canonical decimal Int64 covers both signed endpoints" {
  for
    (text, expected) in [
      ("0", 0L),
      ("1", 1L),
      ("-1", -1L),
      ("2147483648", 2147483648L),
      ("-2147483649", -2147483649L),
      ("9007199254740993", 9007199254740993L),
      ("-9007199254740993", -9007199254740993L),
      ("9223372036854775806", 9223372036854775806L),
      ("9223372036854775807", 9223372036854775807L),
      ("-9223372036854775807", -9223372036854775807L),
      ("-9223372036854775808", -9223372036854775807L - 1L),
    ] {
    assert_eq(read_decimal_int64(text), Ok(expected))
  }
  for
    text in [
      "9223372036854775808", "-9223372036854775809", "9999999999999999999", "-9999999999999999999",
      "10000000000000000000", "-10000000000000000000",
    ] {
    assert_eq(read_decimal_int64(text), Err(RangeExceeded))
  }
}

///|
test "decimal diagnostics check syntax before spelling before range" {
  for
    text in [
      "", "-", "+1", " 1", "1 ", "1\n", "1.0", "1e3", "0x", "00x", "0x000000000000000000000",
      "999999999999999999x", "x999999999999999999", "999999999999999999999999x",
      "-999999999999999999999999x", "１２", "١٢", "−1", "--1", "1-2", "\u0000",
    ] {
    assert_eq(read_decimal_int64(text), Err(InvalidSyntax))
  }
  for
    text in [
      "-0", "00", "01", "-00", "-01", "000000000000000000000000000", "-000000000000000000000000000",
    ] {
    assert_eq(read_decimal_int64(text), Err(NonCanonical))
  }
  // The caller owns an input-size bound; classification does not truncate text.
  assert_eq(read_decimal_int64("9".repeat(10000) + "x"), Err(InvalidSyntax))
  assert_eq(read_decimal_int64("0".repeat(10000)), Err(NonCanonical))
  assert_eq(read_decimal_int64("9".repeat(10000)), Err(RangeExceeded))
}

///|
test "binary64 narrowing checks exact Int32 and safe-integer boundaries" {
  for
    (number, expected) in [
      (-2147483648.0, -2147483647 - 1),
      (2147483647.0, 2147483647),
      (-0.0, 0),
    ] {
    assert_eq(read_int32(number), Some(expected))
  }
  for
    number in [
      -2147483649.0,
      2147483648.0,
      0.5,
      -0.5,
      1.0 / 0.0,
      -1.0 / 0.0,
      0.0 / 0.0,
    ] {
    assert_eq(read_int32(number), None)
  }
  assert_eq(read_safe_integer(-9007199254740991.0), Some(-9007199254740991L))
  assert_eq(read_safe_integer(9007199254740991.0), Some(9007199254740991L))
  assert_eq(read_safe_integer(-0.0), Some(0L))
  for
    number in [
      -9007199254740992.0,
      9007199254740992.0,
      -1.5,
      1.5,
      1.0 / 0.0,
      -1.0 / 0.0,
      0.0 / 0.0,
    ] {
    assert_eq(read_safe_integer(number), None)
  }
}

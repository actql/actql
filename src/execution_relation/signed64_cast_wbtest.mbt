///|
test "SQL signed64 conversion accepts input spelling without relaxing canonical wire admission" {
  for
    (text, expected) in [
      ("+00012", 12L),
      ("-0", 0L),
      ("  +12\t", 12L),
      ("\t12\r\n", 12L),
      ("+0X7f", 127L),
      ("-0x8000000000000000", -9223372036854775807L - 1L),
      ("0x7fffffffffffffff", 9223372036854775807L),
    ] {
    assert_eq(cast_signed64_text(text), Some(expected), msg=text)
  }
  for
    text in [
      "", " ", "+", "-", "0x", "+0x", "--1", "1.0", "1e0", "12x", "1 2", "１２",
      "\t0x12", "9223372036854775808", "-9223372036854775809", "0x8000000000000000",
      "-0x8000000000000001",
    ] {
    assert_eq(cast_signed64_text(text), None, msg=text)
  }
}

///|
test "SQL signed64 conversion rounds explicit Number casts without losing integer bits or wrapping" {
  for
    (number, expected) in [
      (1.4, 1L),
      (1.5, 2L),
      (-1.5, -2L),
      (-0.5, -1L),
      (0.49999999999999994, 0L),
      (4503599627370497.0, 4503599627370497L),
      (9223372036854774784.0, 9223372036854774784L),
      (-9223372036854775808.0, -9223372036854775807L - 1L),
    ] {
    assert_true(
      cast_signed64_value(Number(number))
      is Some(Captured(@admitted.Signed64(value))) &&
      value == expected,
    )
  }
  assert_true(cast_signed64_value(Number(9223372036854775808.0)) is None)
  assert_true(cast_signed64_value(Number(-9223372036854777856.0)) is None)
}

///|
test "SQL signed64 conversion rounds the original Decimal coefficient exactly" {
  for
    (coefficient, scale, expected) in [
      ("5", 2, 0L),
      ("5", 1, 1L),
      ("-5", 1, -1L),
      ("12345", 2, 123L),
      ("12350", 2, 124L),
      ("-12350", 2, -124L),
      ("92233720368547758074", 1, 9223372036854775807L),
      ("-92233720368547758084", 1, -9223372036854775807L - 1L),
    ] {
    let original = @admitted.decimal_from_coefficient(coefficient, 38, scale).unwrap()
    assert_true(
      cast_signed64_value(capture(original))
      is Some(Captured(@admitted.Signed64(value))) &&
      value == expected,
      msg=coefficient,
    )
  }
  for coefficient in ["92233720368547758075", "-92233720368547758085"] {
    let original = @admitted.decimal_from_coefficient(coefficient, 38, 1).unwrap()
    assert_true(cast_signed64_value(capture(original)) is None)
  }
}

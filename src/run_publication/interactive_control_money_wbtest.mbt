///|
test "interactive money exact Int64 domain independent boundaries" {
  assert_eq(parse_control_amount_micro("0"), Ok(0L))
  assert_eq(
    parse_control_amount_micro("9007199254740993"),
    Ok(9007199254740993L),
  )
  assert_eq(
    parse_control_amount_micro("9223372036854775806"),
    Ok(9223372036854775806L),
  )
  assert_eq(
    parse_control_amount_micro("9223372036854775807"),
    Ok(9223372036854775807L),
  )
  assert_eq(
    parse_control_amount_micro("9223372036854775808"),
    Err(ControlAmountOverflow),
  )
  for text in ["", "00", "01", "+1", "-1", "1e3", "1.0", " 1", "1\n"] {
    assert_eq(parse_control_amount_micro(text), Err(InvalidControlAmount))
  }
}

///|
test "interactive money facade decimals are exact and do not select a tariff" {
  assert_eq(normalize_control_amount_decimal("5.00"), Ok("5000000"))
  assert_eq(normalize_control_amount_decimal("0.000001"), Ok("1"))
  assert_eq(
    normalize_control_amount_decimal("9007199254.740993"),
    Ok("9007199254740993"),
  )
  assert_eq(
    normalize_control_amount_decimal("9223372036854.775807"),
    Ok("9223372036854775807"),
  )
  assert_eq(
    normalize_control_amount_decimal("9223372036854.775808"),
    Err(ControlAmountOverflow),
  )
  for text in ["5.", ".5", "01.00", "0.0000001", "1e2", "-1", "+1", "5.00 "] {
    assert_eq(normalize_control_amount_decimal(text), Err(InvalidControlAmount))
  }
}

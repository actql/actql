///|
test "decimal negate preserves the admitted numeric contract" {
  let operand = Captured(
    @admitted.decimal_from_coefficient("1250", 8, 3).unwrap(),
  )
  let first = unary(@lower.Negate, operand)
  assert_true(
    first is Ok(Captured(@admitted.Decimal(d))) &&
      d.coefficient == "-1250" && d.precision == 8 && d.scale == 3,
    msg=if first is Err(InvalidOperand) {
      "Negate decimal: InvalidOperand"
    } else {
      "decimal negate did not retain type and value"
    },
  )
  guard first is Ok(value) else { fail("first negate failed") }
  assert_true(
    unary(@lower.Negate, value) is Ok(Captured(@admitted.Decimal(d))) &&
      d.coefficient == "1250" && d.precision == 8 && d.scale == 3,
  )
}

///|
test "decimal negate keeps NULL and canonical zero semantics" {
  assert_true(unary(@lower.Negate, Null) is Ok(Null))
  let zero = Captured(
    @admitted.decimal_from_coefficient("0", 38, 6).unwrap(),
  )
  guard unary(@lower.Negate, zero) is Ok(Captured(
    @admitted.Decimal(result),
  )) else {
    fail("zero decimal negate failed")
  }
  assert_eq(result.coefficient, "0")
  assert_eq(result.precision, 38)
  assert_eq(result.scale, 6)
  let negative = Captured(
    @admitted.decimal_from_coefficient("-9", 4, 1).unwrap(),
  )
  guard unary(@lower.Negate, negative) is Ok(Captured(
    @admitted.Decimal(result),
  )) else {
    fail("negative decimal negate failed")
  }
  assert_eq(result.coefficient, "9")
  assert_eq(result.precision, 4)
  assert_eq(result.scale, 1)
}

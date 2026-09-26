///|
fn text_order_sign(left : CheckedValue, right : CheckedValue) -> Int {
  let compared = @canonical.compare_utf16(
    typed_key_order_text(left).unwrap(),
    typed_key_order_text(right).unwrap(),
  )
  if compared < 0 {
    -1
  } else if compared > 0 {
    1
  } else {
    0
  }
}

///|
fn assert_text_order_agrees(values : Array[CheckedValue]) -> Unit raise {
  for left in values {
    for right in values {
      assert_eq(
        Ok(text_order_sign(left, right)),
        compare_key_values(left, right),
      )
    }
  }
}

///|
test "typed key order text agrees with binary64 key order" {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let values = [
    -1.0e300, -10.0, -9.0, -1.5, -1.0, -5.0e-324, 0.0, 5.0e-324, 2.2e-308, 0.1, 1.0,
    1.5, 2.0, 9.0, 10.0, 11.0, 100.0, 9007199254740993.0, 1.0e300,
  ].map(value => checked_key(number, Number(value)))
  assert_text_order_agrees(values)
  // Graph snapshot identity needs 9 before 10.
  assert_eq(text_order_sign(values[13], values[14]), -1)
}

///|
test "typed key order text agrees with exact decimal key order" {
  let decimal = fn(coefficient : String, precision : Int, scale : Int) {
    checked_key(
      @contract.decimal_contract(38, scale, nullable=false).unwrap(),
      Decimal({ coefficient, precision, scale, }),
    )
  }
  let values = [
    decimal("-1230", 4, 1),
    decimal("-123", 3, 1),
    decimal("-1234", 4, 2),
    decimal("-12", 2, 1),
    decimal("-120", 3, 2),
    decimal("-1", 1, 0),
    decimal("-5", 1, 3),
    decimal("0", 1, 0),
    decimal("5", 1, 3),
    decimal("50", 2, 4),
    decimal("1", 1, 0),
    decimal("100", 3, 2),
    decimal("12", 2, 1),
    decimal("121", 3, 2),
    decimal("1234", 4, 2),
    decimal("9", 1, 0),
    decimal("10", 2, 0),
    decimal("99999999999999999999999999999999999999", 38, 0),
  ]
  assert_text_order_agrees(values)
}

///|
test "typed key order text agrees for booleans, text and dates" {
  let boolean = @contract.primitive(@contract.BooleanType, nullable=false)
  assert_text_order_agrees([
    checked_key(boolean, Boolean(false)),
    checked_key(boolean, Boolean(true)),
  ])
  let text = @contract.primitive(@contract.StringType, nullable=false)
  assert_text_order_agrees(
    ["", "a", "ab", "b", "", "𐀀", "10", "9"].map(value => {
      checked_key(text, Text(value))
    }),
  )
  let date = @contract.primitive(@contract.DateType, nullable=false)
  assert_text_order_agrees(
    ["2026-01-02", "2026-01-10", "2026-12-31"].map(value => {
      checked_key(date, Date(value))
    }),
  )
}

///|
test "typed key order text has no key for null or non-key values" {
  let nullable = @contract.primitive(@contract.StringType, nullable=true)
  assert_eq(typed_key_order_text(checked_key(nullable, Null)), Err(InvalidKey))
  // A present component of a nullable contract still has its key.
  assert_eq(typed_key_order_text(checked_key(nullable, Text("x"))), Ok("x"))
}

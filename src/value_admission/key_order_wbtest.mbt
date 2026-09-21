///|
fn checked_key(contract : @contract.Contract, value : Value) -> CheckedValue {
  { contract, value, }
}

///|
test "key order preserves primitive and UTF16 semantics" {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  assert_eq(
    compare_key_values(
      checked_key(number, Number(2.0)),
      checked_key(number, Number(10.0)),
    ),
    Ok(-1),
  )
  let boolean = @contract.primitive(@contract.BooleanType, nullable=false)
  assert_eq(
    compare_key_values(
      checked_key(boolean, Boolean(false)),
      checked_key(boolean, Boolean(true)),
    ),
    Ok(-1),
  )
  let text = @contract.primitive(@contract.StringType, nullable=false)
  assert_eq(
    compare_key_values(
      checked_key(text, Text("𐀀")),
      checked_key(text, Text("\ue000")),
    ),
    Ok(-1),
  )
}

///|
test "key order compares decimal coefficients without binary64 conversion" {
  let tenth = @contract.decimal_contract(2, 1, nullable=false).unwrap()
  let hundredth = @contract.decimal_contract(3, 2, nullable=false).unwrap()
  assert_eq(
    compare_key_values(
      checked_key(
        tenth,
        Decimal({ coefficient: "12", precision: 2, scale: 1, }),
      ),
      checked_key(
        hundredth,
        Decimal({ coefficient: "121", precision: 3, scale: 2, }),
      ),
    ),
    Ok(-1),
  )
}

///|
test "author order accepts nullable values and places null last" {
  let nullable = @contract.primitive(@contract.StringType, nullable=true)
  let required = @contract.primitive(@contract.StringType, nullable=false)
  let text = checked_key(nullable, Text("x"))
  let null = checked_key(nullable, Null)
  assert_eq(compare_key_values(text, text), Err(InvalidKey))
  assert_eq(compare_author_order_values(text, text), Ok(0))
  assert_eq(compare_author_order_values(text, null), Ok(-1))
  assert_eq(compare_author_order_values(null, text), Ok(1))
  assert_eq(compare_author_order_values(null, null), Ok(0))
  assert_eq(
    compare_author_order_values(checked_key(required, Null), text),
    Err(InvalidKey),
  )
}

///|
test "group key order accepts nullable values and places null first" {
  let nullable = @contract.primitive(@contract.StringType, nullable=true)
  let required = @contract.primitive(@contract.StringType, nullable=false)
  let text = checked_key(nullable, Text("x"))
  let null = checked_key(nullable, Null)
  assert_eq(compare_group_key_values(text, text), Ok(0))
  assert_eq(compare_group_key_values(text, null), Ok(1))
  assert_eq(compare_group_key_values(null, text), Ok(-1))
  assert_eq(compare_group_key_values(null, null), Ok(0))
  assert_eq(
    compare_group_key_values(checked_key(required, Null), text),
    Err(InvalidKey),
  )
}

///|
test "checked numbers reject the wrong contract and negative zero" {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let text = @contract.primitive(@contract.StringType, nullable=false)
  assert_true(checked_number_value(1.0, number) is Some(_))
  assert_true(checked_number_value(1.0, text) is None)
  assert_true(checked_number_value(-0.0, number) is None)
}

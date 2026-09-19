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
test "checked numbers reject the wrong contract and negative zero" {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let text = @contract.primitive(@contract.StringType, nullable=false)
  assert_true(checked_number_value(1.0, number) is Some(_))
  assert_true(checked_number_value(1.0, text) is None)
  assert_true(checked_number_value(-0.0, number) is None)
}

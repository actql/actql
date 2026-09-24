///|
fn checked_key(contract : @contract.Contract, value : Value) -> CheckedValue {
  { contract, value, }
}

///|
fn bounded_key_order(
  left : CheckedValue,
  right : CheckedValue,
  quantum : Int,
) -> Result[(Int, Int), KeyOrderIssue] {
  let active = match start_bounded_key_comparison(left, right) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut work = 0
  while true {
    let poll = match advance_bounded_key_comparison(active, quantum) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match poll {
      KeyComparisonContinue(work=used) => work += used
      KeyComparisonComplete(order~, work=used) =>
        return Ok((order, work + used))
    }
  } nobreak {
    Err(InvalidKey)
  }
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

///|
test "bounded key order preserves typed order across long prefixes" {
  let text = @contract.primitive(@contract.StringType, nullable=false)
  let prefix = "x".repeat(512)
  let smaller = checked_key(text, Text(prefix + "a"))
  let larger = checked_key(text, Text(prefix + "b"))
  assert_eq(compare_key_values(smaller, larger), Ok(-1))
  assert_eq(bounded_key_order(smaller, larger, 1), Ok((-1, 513)))
  let active = start_bounded_key_comparison(smaller, larger).unwrap()
  for _ in 0..<100 {
    assert_true(
      advance_bounded_key_comparison(active, 1)
      is Ok(KeyComparisonContinue(work=1)),
    )
  }
  assert_eq(
    bounded_key_order(
      checked_key(text, Text("\u{10000}")),
      checked_key(text, Text("\u{e000}")),
      1,
    ).unwrap().0,
    -1,
  )
  let decimal_a = @contract.decimal_contract(2, 1, nullable=false).unwrap()
  let decimal_b = @contract.decimal_contract(3, 2, nullable=false).unwrap()
  let left = checked_key(
    decimal_a,
    Decimal({ coefficient: "12", precision: 2, scale: 1, }),
  )
  let right = checked_key(
    decimal_b,
    Decimal({ coefficient: "121", precision: 3, scale: 2, }),
  )
  assert_eq(bounded_key_order(left, right, 1).unwrap().0, -1)
  assert_eq(compare_key_values(left, right), Ok(-1))
  let nullable = @contract.primitive(@contract.StringType, nullable=true)
  assert_true(
    start_bounded_key_comparison(
      checked_key(nullable, Text("x")),
      checked_key(nullable, Text("x")),
    )
    is Err(InvalidKey),
  )
}

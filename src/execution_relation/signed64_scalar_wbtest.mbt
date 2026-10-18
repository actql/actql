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

///|
test "signed64 original input keys retain exact atoms and fixed scalar accounting" {
  let first = input_key_admitted_atom(
    @admitted.signed64_value(9007199254740992L),
    0,
  ).unwrap()
  let second = input_key_admitted_atom(
    @admitted.signed64_value(9007199254740993L),
    1,
  ).unwrap()
  assert_false(first == second)
  assert_false(second == KeyText("9007199254740993"))
  assert_false(second == KeyDecimal("9007199254740993", 0))
  let keys : Map[KeyAtom, Int] = Map([])
  keys[first] = 0
  keys[second] = 1
  assert_eq(keys.length(), 2)
  assert_eq(keys.get(first), Some(0))
  assert_eq(keys.get(second), Some(1))
  let budget = value_budget({
    max_nodes: 1,
    max_depth: 0,
    max_text_bytes: 0,
    max_work: 1,
  }).unwrap()
  assert_true(
    measure(@admitted.signed64_value(-9223372036854775808L), 0, budget),
  )
  assert_eq((budget.nodes, budget.text, budget.work), (1, 0, 1))
}

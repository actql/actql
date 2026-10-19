///|
test "to_number retains the existing canonical CAST and original operand" {
  for name in ["TO_NUMBER", "to_number", "To_NuMbEr", "`to_number`"] {
    for child in ["'12.5'", "12.5", "NULL", "@input", "amount", "1 / 0"] {
      assert_eq(
        emit(name + "(" + child + ")"),
        emit("CAST(" + child + " AS NUMBER)"),
      )
    }
  }
}

///|
test "to_number retains arity namespace and bounded lowering refusal" {
  for args in ["", "'1', '2'"] {
    assert_true(
      lower(fixture("to_number(" + args + ")"), _ => None, limits())
      is Err({ issue: InvalidArguments, .. }),
    )
  }
  assert_true(
    lower(fixture("ACTQL.to_number('1')"), _ => None, limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
  assert_true(
    lower(fixture("to_number('1')"), _ => None, { ..limits(), max_work: 0, })
    is Err({ issue: WorkLimit, .. }),
  )
}

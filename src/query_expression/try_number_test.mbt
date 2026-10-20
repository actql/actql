///|
test "TRY_NUMBER preserves the original closed text conversion operand" {
  for name in ["TRY_NUMBER", "try_number", "TrY_NuMbEr", "`try_number`"] {
    for
      (input, expected) in [
        ("'12.5'", "{\"literal\":\"12.5\"}"),
        ("'not-a-number'", "{\"literal\":\"not-a-number\"}"),
        ("NULL", "{\"literal\":null}"),
        ("@input", "{\"$param\":\"input\"}"),
        ("amount", "{\"field\":\"amount\"}"),
        ("1 / 0", "{\"divide\":[{\"literal\":1},{\"literal\":0}]}"),
      ] {
      assert_eq(
        emit(name + "(" + input + ")"),
        "{\"try_number\":{\"value\":" + expected + "}}",
      )
    }
  }
}

///|
test "TRY_NUMBER retains arity namespace reference and work refusals" {
  for args in ["", "'1', '2'"] {
    assert_true(
      lower(fixture("TRY_NUMBER(" + args + ")"), _ => None, limits())
      is Err({ issue: InvalidArguments, .. }),
    )
  }
  assert_true(
    lower(fixture("ACTQL.TRY_NUMBER('1')"), _ => None, limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
  assert_true(
    lower(fixture("TRY_NUMBER(amount)"), _ => None, limits())
    is Err({ issue: UnknownReference, .. }),
  )
  assert_true(
    lower(fixture("TRY_NUMBER('1')"), _ => None, { ..limits(), max_work: 0, })
    is Err({ issue: WorkLimit, .. }),
  )
}

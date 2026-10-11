///|
test "GoogleSQL SPLIT preserves ordinary optional delimiter expressions" {
  for spelling in ["SPLIT", "split", "`SPLIT`"] {
    assert_eq(emit(spelling + "(s)"), "{\"split\":[{\"field\":\"s\"}]}")
    assert_eq(
      emit(spelling + "(s,@d)"),
      "{\"split\":[{\"field\":\"s\"},{\"$param\":\"d\"}]}",
    )
    assert_eq(
      emit(spelling + "(s,LOWER(d))"),
      "{\"split\":[{\"field\":\"s\"},{\"lower\":{\"field\":\"d\"}}]}",
    )
    for args in ["", "'a',',','x'"] {
      assert_true(
        lower(fixture(spelling + "(" + args + ")"), _ => None, limits())
        is Err({ issue: InvalidArguments, .. }),
      )
    }
  }
  assert_true(
    lower(fixture("ACTQL.SPLIT('a')"), _ => None, limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
  assert_true(
    same_scalar_function(
      scalar_identity_name("split"),
      scalar_identity_name("SPLIT", quoted=true),
    ),
  )
}

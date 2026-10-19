///|
test "CONTAINS uses the original exact predicate and preserves every child" {
  for name in ["CONTAINS", "contains", "cOnTaInS", "`CoNtAiNs`"] {
    assert_eq(
      emit(name + "(label, @part)"),
      "{\"contains\":[{\"field\":\"label\"},{\"$param\":\"part\"}]}",
    )
    assert_eq(
      emit(name + "(NULL, 'é')"),
      "{\"contains\":[{\"literal\":null},{\"literal\":\"é\"}]}",
    )
    assert_eq(
      emit(name + "('😀x', '')"),
      "{\"contains\":[{\"literal\":\"😀x\"},{\"literal\":\"\"}]}",
    )
  }
}

///|
test "CONTAINS retains exact arity namespace and existing budgets" {
  for args in ["", "'a'", "'a','b','c'"] {
    assert_true(
      lower(fixture("CONTAINS(" + args + ")"), _ => None, limits())
      is Err({ issue: InvalidArguments, .. }),
    )
  }
  assert_true(
    lower(fixture("ACTQL.CONTAINS('a','b')"), _ => None, limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
  assert_true(
    lower(fixture("CONTAINS('a','b')"), _ => None, { ..limits(), max_work: 0, })
    is Err({ issue: WorkLimit, .. }),
  )
}

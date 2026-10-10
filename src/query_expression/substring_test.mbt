///|
test "SUBSTR and SUBSTRING share common canonical body and optional length" {
  for name in ["SUBSTR", "SUBSTRING", "sUbStR", "`SuBsTrInG`"] {
    assert_eq(
      emit(name + "(x, 0)"),
      "{\"substring\":{\"start\":{\"literal\":0},\"value\":{\"field\":\"x\"}}}",
    )
    assert_eq(
      emit(name + "(x, -2, @n)"),
      "{\"substring\":{\"length\":{\"$param\":\"n\"},\"start\":{\"literal\":-2},\"value\":{\"field\":\"x\"}}}",
    )
    assert_eq(
      emit(name + "(NULL, 1, NULL)"),
      "{\"substring\":{\"length\":{\"literal\":null},\"start\":{\"literal\":1},\"value\":{\"literal\":null}}}",
    )
    for args in ["", "'x'", "'x',1,2,3"] {
      assert_true(
        lower(fixture(name + "(" + args + ")"), _ => None, limits())
        is Err({ issue: InvalidArguments, .. }),
      )
    }
    assert_true(
      lower(fixture("ACTQL." + name + "('x',1)"), _ => None, limits())
      is Err({ issue: UnsupportedFunction, .. }),
    )
  }
}

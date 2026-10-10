///|
test "GoogleSQL scalar spellings lower to one ordered common operation" {
  for text in ["SIGN(x)", "sign(x)", "`SiGn`(x)"] {
    assert_eq(emit(text), "{\"sign\":{\"field\":\"x\"}}")
  }
  assert_eq(
    emit("STARTS_WITH(x, @p)"),
    "{\"starts_with\":[{\"field\":\"x\"},{\"$param\":\"p\"}]}",
  )
  assert_eq(
    emit("`EnDs_WiTh`(x, '')"),
    "{\"ends_with\":[{\"field\":\"x\"},{\"literal\":\"\"}]}",
  )
  assert_eq(
    emit("SIGN(IF(TRUE, -2, 1 / 0))"),
    "{\"sign\":{\"if\":[{\"literal\":true},{\"literal\":-2},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]}}",
  )
}

///|
test "GoogleSQL scalar arities and namespaces stay closed" {
  for
    text in [
      "SIGN()", "SIGN(1, 2)", "STARTS_WITH('a')", "STARTS_WITH('a', 'b', 'c')", "ENDS_WITH()",
    ] {
    assert_true(
      lower(fixture(text), _ => None, limits())
      is Err({ issue: InvalidArguments, .. }),
    )
  }
  for
    text in [
      "ACTQL.SIGN(1)", "ACTQL.STARTS_WITH('a', 'a')", "SAFE_DIVIDE(1, 0)", "CONTAINS_SUBSTR('a', 'A')",
    ] {
    assert_true(
      lower(fixture(text), _ => None, limits())
      is Err({ issue: UnsupportedFunction, .. }),
    )
  }
}

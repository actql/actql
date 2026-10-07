///|
test "ceiling uses existing numeric operators and one operand subtree" {
  assert_eq(
    emit("CEIL(x)"),
    "{\"negate\":{\"floor\":{\"subtract\":[{\"literal\":0},{\"field\":\"x\"}]}}}",
  )
  assert_eq(
    emit("ceiling(@p)"),
    "{\"negate\":{\"floor\":{\"subtract\":[{\"literal\":0},{\"$param\":\"p\"}]}}}",
  )
  assert_eq(
    emit("CEIL(IF(TRUE, 2.3, 1 / 0))"),
    "{\"negate\":{\"floor\":{\"subtract\":[{\"literal\":0},{\"if\":[{\"literal\":true},{\"literal\":2.3},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]}]}}}",
  )
}

///|
test "ceiling arity is explicit and foreign or quoted function names stay rejected" {
  for text in ["CEIL()", "CEILING(1, 2)"] {
    assert_true(
      lower(fixture(text), _ => None, limits())
      is Err({ issue: InvalidArguments, .. }),
    )
  }
  for text in ["ACTQL.CEIL(1)", "`CEIL`(1)"] {
    assert_true(
      lower(fixture(text), _ => None, limits())
      is Err({ issue: UnsupportedFunction, .. }),
    )
  }
}

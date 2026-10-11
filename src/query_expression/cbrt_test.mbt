///|
test "GoogleSQL cbrt spellings retain a distinct canonical unary operation" {
  for spelling in ["CBRT", "cbrt", "cBrT", "`CBRT`"] {
    assert_eq(emit(spelling + "(@n)"), "{\"cbrt\":{\"$param\":\"n\"}}")
    assert_eq(emit(spelling + "(NULL)"), "{\"cbrt\":{\"literal\":null}}")
    for args in ["", "1,2", "1,2,3"] {
      assert_true(
        lower(fixture(spelling + "(" + args + ")"), _ => None, limits())
        is Err({ issue: InvalidArguments, .. }),
      )
    }
  }
  assert_true(
    lower(fixture("SAFE.CBRT(8)"), _ => None, limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
  assert_true(
    lower(fixture("ACTQL.CBRT(8)"), _ => None, limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
  assert_true(
    same_scalar_function(
      scalar_identity_name("cbrt"),
      scalar_identity_name("CBRT", quoted=true),
    ),
  )
  assert_false(
    same_scalar_function(
      scalar_identity_name("cbrt"),
      scalar_identity_name("sqrt"),
    ),
  )
}

///|
test "IFNULL lowers once to the common two-argument lazy coalesce" {
  assert_eq(
    emit("IFNULL(NULL, 7)"),
    "{\"coalesce\":[{\"literal\":null},{\"literal\":7}]}",
  )
  assert_eq(
    emit("ifnull(x, @fallback)"),
    "{\"coalesce\":[{\"field\":\"x\"},{\"$param\":\"fallback\"}]}",
  )
  assert_eq(
    emit("IFNULL(1, 1 / 0)"),
    "{\"coalesce\":[{\"literal\":1},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]}",
  )
}

///|
test "IFNULL keeps exact arity and the closed function namespace" {
  for text in ["IFNULL()", "IFNULL(1)", "IFNULL(1, 2, 3)"] {
    assert_true(
      lower(fixture(text), _ => None, limits())
      is Err({ issue: InvalidArguments, .. }),
      msg=text,
    )
  }
  for text in ["ACTQL.IFNULL(1, 2)", "`IFNULL`(1, 2)"] {
    assert_true(
      lower(fixture(text), _ => None, limits())
      is Err({ issue: UnsupportedFunction, .. }),
      msg=text,
    )
  }
}

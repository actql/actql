///|
// Independently authored common wire forms; not evaluator-generated fixtures.
test "GoogleSQL STRPOS retains ordered operands in the common owner" {
  for text in ["STRPOS(x, @p)", "strpos(x, @p)", "`StRpOs`(x, @p)"] {
    assert_eq(emit(text), "{\"strpos\":[{\"field\":\"x\"},{\"$param\":\"p\"}]}")
  }
  assert_eq(
    emit("STRPOS('😀a', 'a')"),
    "{\"strpos\":[{\"literal\":\"😀a\"},{\"literal\":\"a\"}]}",
  )
}

///|
test "GoogleSQL STRPOS arity and namespace are closed before execution" {
  for text in ["STRPOS()", "STRPOS('a')", "STRPOS('a', 'b', 'c')"] {
    assert_true(
      lower(fixture(text), _ => None, limits())
      is Err({ issue: InvalidArguments, .. }),
    )
  }
  assert_true(
    lower(fixture("ACTQL.STRPOS('a', 'a')"), _ => None, limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
}

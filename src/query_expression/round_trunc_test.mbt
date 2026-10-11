///|
// Independent common wire forms; no emitted expression constructs the oracle.
test "unary ROUND and TRUNC spellings retain their common owner" {
  for
    (names, op) in [
      (["ROUND", "round", "`RoUnD`"], "round"),
      (["TRUNC", "trunc", "`TrUnC`"], "trunc"),
    ] {
    for name in names {
      assert_eq(emit(name + "(x)"), "{\"" + op + "\":{\"field\":\"x\"}}")
      assert_eq(emit(name + "(@p)"), "{\"" + op + "\":{\"$param\":\"p\"}}")
    }
  }
  assert_eq(emit("ROUND(-2.5)"), "{\"round\":{\"literal\":-2.5}}")
  assert_eq(emit("TRUNC(NULL)"), "{\"trunc\":{\"literal\":null}}")
}

///|
test "unary rounding retains demanded and lazy child expressions" {
  assert_eq(
    emit("ROUND(1 / 0)"),
    "{\"round\":{\"divide\":[{\"literal\":1},{\"literal\":0}]}}",
  )
  assert_eq(
    emit("TRUNC(IF(TRUE, -2.5, 1 / 0))"),
    "{\"trunc\":{\"if\":[{\"literal\":true},{\"literal\":-2.5},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]}}",
  )
}

///|
test "rounding rejects unsupported arity and rounding mode before execution" {
  for name in ["ROUND", "TRUNC"] {
    for arguments in ["", "2.5, 0, 'ROUND_HALF_EVEN'"] {
      assert_true(
        lower(fixture(name + "(" + arguments + ")"), _ => None, limits())
        is Err({ issue: InvalidArguments, .. }),
      )
    }
    assert_true(
      lower(fixture("ACTQL." + name + "(2.5)"), _ => None, limits())
      is Err({ issue: UnsupportedFunction, .. }),
    )
  }
}

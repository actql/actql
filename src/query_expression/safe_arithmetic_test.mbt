///|
test "SAFE arithmetic spellings lower to distinct closed common owners" {
  for
    (op, upper, mixed) in [
      ("safe_add", "SAFE_ADD", "SaFe_AdD"),
      ("safe_subtract", "SAFE_SUBTRACT", "SaFe_SuBtRaCt"),
      ("safe_multiply", "SAFE_MULTIPLY", "SaFe_MuLtIpLy"),
      ("safe_divide", "SAFE_DIVIDE", "SaFe_DiViDe"),
    ] {
    for name in [op, upper, "`" + mixed + "`"] {
      assert_eq(
        emit(name + "(x, @p)"),
        "{\"" + op + "\":[{\"field\":\"x\"},{\"$param\":\"p\"}]}",
      )
    }
    assert_eq(
      emit(op + "(1 / 0, NULL)"),
      "{\"" +
      op +
      "\":[{\"divide\":[{\"literal\":1},{\"literal\":0}]},{\"literal\":null}]}",
    )
  }
  for name in ["safe_negate", "SAFE_NEGATE", "`SaFe_NeGaTe`"] {
    assert_eq(emit(name + "(x)"), "{\"safe_negate\":{\"field\":\"x\"}}")
  }
}

///|
test "SAFE arithmetic rejects arity qualified names and the legacy safe_div alias" {
  for op in ["SAFE_ADD", "SAFE_SUBTRACT", "SAFE_MULTIPLY", "SAFE_DIVIDE"] {
    for args in ["", "1", "1, 2, 3"] {
      assert_true(
        lower(fixture(op + "(" + args + ")"), _ => None, limits())
        is Err({ issue: InvalidArguments, .. }),
      )
    }
    assert_true(
      lower(fixture("ACTQL." + op + "(1, 2)"), _ => None, limits())
      is Err({ issue: UnsupportedFunction, .. }),
    )
  }
  for args in ["", "1, 2"] {
    assert_true(
      lower(fixture("SAFE_NEGATE(" + args + ")"), _ => None, limits())
      is Err({ issue: InvalidArguments, .. }),
    )
  }
  assert_true(
    lower(fixture("SAFE_DIV(1, 0)"), _ => None, limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
}

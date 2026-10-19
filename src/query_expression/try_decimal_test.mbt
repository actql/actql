///|
test "explicit TRY_DECIMAL retains its original nullable conversion body" {
  for name in ["TRY_DECIMAL", "try_decimal", "`TrY_DeCiMaL`"] {
    assert_eq(
      emit(name + "(@amount,(4),(2))"),
      "{\"try_decimal\":{\"precision\":4,\"scale\":2,\"value\":{\"$param\":\"amount\"}}}",
    )
    assert_eq(
      emit(name + "(NULL,4,2)"),
      "{\"try_decimal\":{\"precision\":4,\"scale\":2,\"value\":{\"literal\":null}}}",
    )
  }
}

///|
test "explicit TRY_DECIMAL refuses absent dynamic or invalid target literals" {
  for
    text in [
      "TRY_DECIMAL(amount, 4)", "TRY_DECIMAL(amount, 4, 2, 0)", "TRY_DECIMAL(amount, 0, 0)",
      "TRY_DECIMAL(amount, 39, 0)", "TRY_DECIMAL(amount, 4, 5)", "TRY_DECIMAL(amount, 4, -1)",
      "TRY_DECIMAL(amount, 1.5, 0)", "TRY_DECIMAL(amount, 4, 1.5)", "TRY_DECIMAL(amount, @precision, 2)",
      "TRY_DECIMAL(amount, 4, @scale)", "TRY_DECIMAL(amount, 2 + 2, 2)", "TRY_DECIMAL(amount, NULL, 2)",
      "TRY_DECIMAL(amount, 4, '2')",
    ] {
    assert_true(
      lower(fixture(text), path => Some(path[0].value), limits())
      is Err({ issue: InvalidArguments, .. }),
      msg=text,
    )
  }
  assert_true(
    lower(fixture("TRY_DECIMAL(amount)"), path => Some(path[0].value), limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
  assert_true(
    lower(
      fixture("ACTQL.TRY_DECIMAL(amount, 4, 2)"),
      path => Some(path[0].value),
      limits(),
    )
    is Err({ issue: UnsupportedFunction, .. }),
  )
  assert_true(
    lower(fixture("TRY_DECIMAL(amount, 4, 2)"), _ => None, limits())
    is Err({ issue: UnknownReference, .. }),
  )
  assert_true(
    lower(fixture("TRY_DECIMAL(amount, 4, 2)"), _ => None, {
      ..limits(),
      max_work: 0,
    })
    is Err({ issue: WorkLimit, .. }),
  )
}

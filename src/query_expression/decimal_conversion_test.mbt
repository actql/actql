///|
test "explicit TO_DECIMAL retains the original Decimal CAST body and one operand" {
  for name in ["TO_DECIMAL", "to_decimal", "To_DeCiMaL", "`to_decimal`"] {
    assert_eq(
      emit(name + "('19.99', 4, 2)"),
      emit("CAST('19.99' AS DECIMAL(4,2))"),
    )
    assert_eq(
      emit(name + "(@amount, (38), (0))"),
      "{\"cast\":{\"target\":{\"precision\":38,\"scale\":0,\"type\":\"decimal\"},\"value\":{\"$param\":\"amount\"}}}",
    )
    assert_eq(emit(name + "(NULL, 4, 2)"), emit("CAST(NULL AS DECIMAL(4,2))"))
    assert_eq(
      emit(name + "(CAST(@amount AS DECIMAL(8,4)), 6, 2)"),
      emit("CAST(CAST(@amount AS DECIMAL(8,4)) AS DECIMAL(6,2))"),
    )
  }
}

///|
test "explicit TO_DECIMAL refuses absent dynamic or invalid target literals" {
  for
    text in [
      "TO_DECIMAL(amount, 4)", "TO_DECIMAL(amount, 4, 2, 0)", "TO_DECIMAL(amount, 0, 0)",
      "TO_DECIMAL(amount, 39, 0)", "TO_DECIMAL(amount, 4, 5)", "TO_DECIMAL(amount, 4, -1)",
      "TO_DECIMAL(amount, 1.5, 0)", "TO_DECIMAL(amount, 4, 1.5)", "TO_DECIMAL(amount, @precision, 2)",
      "TO_DECIMAL(amount, 4, @scale)", "TO_DECIMAL(amount, 2 + 2, 2)", "TO_DECIMAL(amount, NULL, 2)",
      "TO_DECIMAL(amount, 4, '2')",
    ] {
    assert_true(
      lower(fixture(text), path => Some(path[0].value), limits())
      is Err({ issue: InvalidArguments, .. }),
      msg=text,
    )
  }
  assert_true(
    lower(fixture("TO_DECIMAL(amount)"), path => Some(path[0].value), limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
  assert_true(
    lower(
      fixture("ACTQL.TO_DECIMAL(amount, 4, 2)"),
      path => Some(path[0].value),
      limits(),
    )
    is Err({ issue: UnsupportedFunction, .. }),
  )
  assert_true(
    lower(fixture("TO_DECIMAL(amount, 4, 2)"), _ => None, limits())
    is Err({ issue: UnknownReference, .. }),
  )
  assert_true(
    lower(fixture("TO_DECIMAL(amount, 4, 2)"), _ => None, {
      ..limits(),
      max_work: 0,
    })
    is Err({ issue: WorkLimit, .. }),
  )
}

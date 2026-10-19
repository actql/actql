///|
test "typed NULL ARRAY lowers through the existing lazy conditional without replacing NULL" {
  for text in ["CAST(NULL AS ARRAY<INT64>)", "CAST(((NULL)) AS ARRAY<INT64>)"] {
    assert_eq(
      emit(text),
      "{\"if\":[{\"literal\":false},{\"empty_array\":{\"items\":{\"nullable\":false,\"type\":\"int64\"}}},{\"literal\":null}]}",
    )
  }
  assert_eq(
    emit("ARRAY<INT64>[]"),
    "{\"empty_array\":{\"items\":{\"nullable\":false,\"type\":\"int64\"}}}",
  )
  assert_eq(emit("ARRAY<NUMBER>[]"), emit("ARRAY<FLOAT64>[]"))
  // Source lowering preserves ordinary elements. Common typing, not the
  // constructor annotation, decides whether their logical domains unify.
  assert_eq(
    emit("ARRAY<INT64>[1]"),
    "{\"if\":[{\"literal\":true},{\"array\":[{\"literal\":1}]},{\"empty_array\":{\"items\":{\"nullable\":false,\"type\":\"int64\"}}}]}",
  )
}

///|
test "typed NULL ARRAY does not claim general array conversion or erase budget refusal" {
  for
    text in [
      "CAST(@value AS ARRAY<INT64>)", "CAST([1] AS ARRAY<INT64>)", "CAST(IF(TRUE, NULL, NULL) AS ARRAY<INT64>)",
    ] {
    assert_true(
      lower(fixture(text), _ => None, limits())
      is Err({ issue: UnsupportedCast, origin: Some(_), }),
      msg=text,
    )
  }
  assert_true(
    lower(fixture("CAST(((NULL)) AS ARRAY<INT64>)"), _ => None, {
      ..limits(),
      max_work: 0,
    })
    is Err({ issue: WorkLimit, .. }),
  )
}

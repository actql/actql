///|
test "array construction preserves each existing expression without folding order or duplicates" {
  for text in ["[2, 1, 2]", "ARRAY[2, 1, 2]"] {
    assert_eq(
      emit(text),
      "{\"array\":[{\"literal\":2},{\"literal\":1},{\"literal\":2}]}",
    )
  }
  assert_eq(
    emit("[amount, NULL, amount + @delta]"),
    "{\"array\":[{\"field\":\"amount\"},{\"literal\":null},{\"add\":[{\"field\":\"amount\"},{\"$param\":\"delta\"}]}]}",
  )
  assert_eq(
    emit("[\"e\\u0301\", '\\r\\n']"),
    "{\"array\":[{\"literal\":\"é\"},{\"literal\":\"\\r\\n\"}]}",
  )
}

///|
test "typed arrays reuse common item evidence without casting elements" {
  assert_eq(
    emit("ARRAY<STRING>[]"),
    "{\"empty_array\":{\"items\":{\"nullable\":false,\"type\":\"string\"}}}",
  )
  assert_eq(
    emit("ARRAY<FLOAT64>[2, 1, 2]"),
    "{\"if\":[{\"literal\":true},{\"array\":[{\"literal\":2},{\"literal\":1},{\"literal\":2}]},{\"empty_array\":{\"items\":{\"nullable\":false,\"type\":\"number\"}}}]}",
  )
}

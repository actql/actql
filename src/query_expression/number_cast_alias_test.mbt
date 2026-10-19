///|
test "NUMBER cast retains independent ordinary Number expressions" {
  for target in ["NUMBER", "number", "NuMbEr", "FLOAT64", "DOUBLE"] {
    assert_eq(
      emit("CAST('1.25' AS " + target + ")"),
      "{\"cast\":{\"target\":{\"type\":\"number\"},\"value\":{\"literal\":\"1.25\"}}}",
    )
    assert_eq(
      emit("CAST(NULL AS " + target + ")"),
      "{\"cast\":{\"target\":{\"type\":\"number\"},\"value\":{\"literal\":null}}}",
    )
    assert_eq(
      emit("CAST(@value AS " + target + ")"),
      "{\"cast\":{\"target\":{\"type\":\"number\"},\"value\":{\"$param\":\"value\"}}}",
    )
  }
}

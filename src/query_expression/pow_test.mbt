///|
test "POW and POWER aliases preserve ordered expression children" {
  for name in ["POW", "POWER", "`PoWeR`", "pow"] {
    assert_eq(
      emit(name + "(x, @p)"),
      "{\"pow\":[{\"field\":\"x\"},{\"$param\":\"p\"}]}",
    )
    assert_eq(
      emit(name + "(0, 0)"),
      "{\"pow\":[{\"literal\":0},{\"literal\":0}]}",
    )
    assert_eq(
      emit(name + "(NULL, 1 / 0)"),
      "{\"pow\":[{\"literal\":null},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]}",
    )
  }
}

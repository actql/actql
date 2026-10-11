///|
test "ROUND and TRUNC precision retain both authored children and old unary forms" {
  for
    (name, tag) in [
      ("ROUND", "round"),
      ("TRUNC", "trunc"),
      ("`RoUnD`", "round"),
    ] {
    assert_eq(
      emit(name + "(x, @p)"),
      "{\"" + tag + "\":[{\"field\":\"x\"},{\"$param\":\"p\"}]}",
    )
    assert_eq(
      emit(name + "(1.235, 2)"),
      "{\"" + tag + "\":[{\"literal\":1.235},{\"literal\":2}]}",
    )
    assert_eq(
      emit(name + "(NULL, 1 / 0)"),
      "{\"" +
      tag +
      "\":[{\"literal\":null},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]}",
    )
    assert_eq(emit(name + "(x)"), "{\"" + tag + "\":{\"field\":\"x\"}}")
  }
}

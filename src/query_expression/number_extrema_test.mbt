///|
test "GREATEST and LEAST retain ordered variadic singleton and NULL arguments" {
  for
    (name, tag) in [
      ("GREATEST", "greatest"),
      ("LEAST", "least"),
      ("`GrEaTeSt`", "greatest"),
    ] {
    for
      (args, children) in [
        ("x, @p, x", "[{\"field\":\"x\"},{\"$param\":\"p\"},{\"field\":\"x\"}]"),
        ("7", "[{\"literal\":7}]"),
        ("NULL", "[{\"literal\":null}]"),
        (
          "NULL, 1 / 0", "[{\"literal\":null},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]",
        ),
      ] {
      assert_eq(
        emit(name + "(" + args + ")"),
        "{\"" + tag + "\":" + children + "}",
      )
    }
  }
}

///|
test "query extrema preserve 257 authored arguments without a binary rewrite" {
  for name in ["greatest", "least"] {
    let arguments = Array::make(257, "7").join(",")
    let children = Array::make(257, "{\"literal\":7}").join(",")
    assert_eq(
      emit(name + "(" + arguments + ")"),
      "{\"" + name + "\":[" + children + "]}",
    )
  }
}

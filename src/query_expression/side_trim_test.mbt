///|
// Independent common wire forms; no emitted expression constructs the oracle.
test "unary LTRIM and RTRIM spellings retain their common owner" {
  for
    (names, op) in [
      (["LTRIM", "ltrim", "`LtRiM`"], "ltrim"),
      (["RTRIM", "rtrim", "`RtRiM`"], "rtrim"),
    ] {
    for name in names {
      assert_eq(emit(name + "(x)"), "{\"" + op + "\":{\"field\":\"x\"}}")
      assert_eq(emit(name + "(@p)"), "{\"" + op + "\":{\"$param\":\"p\"}}")
      assert_eq(emit(name + "(NULL)"), "{\"" + op + "\":{\"literal\":null}}")
      assert_eq(
        emit(name + "(' 😀é ')"),
        "{\"" + op + "\":{\"literal\":\" 😀é \"}}",
      )
    }
  }
}

///|
test "unary side trimming retains demanded and lazy child expressions" {
  assert_eq(
    emit("LTRIM(CAST(1 / 0 AS STRING))"),
    "{\"ltrim\":{\"cast\":{\"target\":{\"type\":\"string\"},\"value\":{\"divide\":[{\"literal\":1},{\"literal\":0}]}}}}",
  )
  assert_eq(
    emit("RTRIM(IF(TRUE, ' x ', ' y '))"),
    "{\"rtrim\":{\"if\":[{\"literal\":true},{\"literal\":\" x \"},{\"literal\":\" y \"}]}}",
  )
}

///|
test "side trimming rejects unsupported arities and namespace changes" {
  for name in ["LTRIM", "RTRIM"] {
    for arguments in ["", "'x', ' ', 'y'"] {
      assert_true(
        lower(fixture(name + "(" + arguments + ")"), _ => None, limits())
        is Err({ issue: InvalidArguments, .. }),
      )
    }
    assert_true(
      lower(fixture("ACTQL." + name + "('x')"), _ => None, limits())
      is Err({ issue: UnsupportedFunction, .. }),
    )
  }
}

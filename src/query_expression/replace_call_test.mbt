///|
test "REPLACE preserves operand order values and parameter references" {
  assert_eq(
    emit("REPLACE(value, @pattern, 'X')"),
    "{\"replace\":[{\"field\":\"value\"},{\"$param\":\"pattern\"},{\"literal\":\"X\"}]}",
  )
  assert_eq(
    emit("replace('e\\u0301\\r\\n', '', '\\n')"),
    "{\"replace\":[{\"literal\":\"é\\r\\n\"},{\"literal\":\"\"},{\"literal\":\"\\n\"}]}",
  )
}

///|
test "REPLACE checks arity and does not invent a qualified function alias" {
  for text in ["REPLACE()", "REPLACE('a', 'b')", "REPLACE('a', 'b', 'c', 'd')"] {
    assert_true(
      lower(fixture(text), _ => None, limits())
      is Err({ issue: InvalidArguments, .. }),
      msg=text,
    )
  }
  assert_true(
    lower(fixture("ACTQL.REPLACE('a', 'b', 'c')"), _ => None, limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
}

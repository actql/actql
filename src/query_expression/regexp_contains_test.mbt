///|
test "SQL REGEXP_CONTAINS preserves value and pattern identities" {
  assert_eq(
    emit("REGEXP_CONTAINS(@text, @pattern)"),
    "{\"regex_match\":{\"pattern\":{\"$param\":\"pattern\"},\"value\":{\"$param\":\"text\"}}}",
  )
  assert_eq(
    emit("REGEXP_CONTAINS(NULL, '^a$')"),
    "{\"regex_match\":{\"pattern\":{\"literal\":\"^a$\"},\"value\":{\"literal\":null}}}",
  )
}

///|
test "SQL REGEXP_CONTAINS keeps original arity and namespace refusals" {
  for args in ["", "'a'", "'a','a','m'"] {
    assert_true(
      lower(fixture("REGEXP_CONTAINS(" + args + ")"), _ => None, limits())
      is Err({ issue: InvalidArguments, .. }),
    )
  }
  assert_true(
    lower(fixture("ACTQL.REGEXP_CONTAINS('a','a')"), _ => None, limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
}

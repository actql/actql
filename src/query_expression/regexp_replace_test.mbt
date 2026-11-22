///|
test "SQL REGEXP_REPLACE retains all arguments and selects the GoogleSQL dialect" {
  assert_eq(
    emit("REGEXP_REPLACE(@text, @pattern, @replacement)"),
    "{\"regex_replace\":{\"dialect\":\"googlesql\",\"pattern\":{\"$param\":\"pattern\"},\"replacement\":{\"$param\":\"replacement\"},\"value\":{\"$param\":\"text\"}}}",
  )
}

///|
test "SQL REGEXP_REPLACE accepts exactly three unqualified arguments" {
  for args in ["'a','a'", "'a','a','X','m'"] {
    assert_true(
      lower(fixture("REGEXP_REPLACE(" + args + ")"), _ => None, limits())
      is Err({ issue: InvalidArguments, .. }),
    )
  }
  assert_true(
    lower(fixture("ACTQL.REGEXP_REPLACE('a','a','X')"), _ => None, limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
}

///|
test "SQL REGEXP_EXTRACT preserves both arguments and omits capture selection" {
  assert_eq(
    emit("REGEXP_EXTRACT(@text, @pattern)"),
    "{\"regex_extract\":{\"pattern\":{\"$param\":\"pattern\"},\"value\":{\"$param\":\"text\"}}}",
  )
}

///|
test "SQL REGEXP_EXTRACT refuses unselected arity and namespace" {
  for args in ["'a'", "'a','a',1", "'a','a',1,2"] {
    assert_true(
      lower(fixture("REGEXP_EXTRACT(" + args + ")"), _ => None, limits())
      is Err({ issue: InvalidArguments, .. }),
    )
  }
  assert_true(
    lower(fixture("ACTQL.REGEXP_EXTRACT('a','a')"), _ => None, limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
}

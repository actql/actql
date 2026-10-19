///|
test "CURRENT_TIMESTAMP remains a zero argument canonical operation" {
  for
    text in [
      "CURRENT_TIMESTAMP()", "current_timestamp()", "((CURRENT_TIMESTAMP()))",
    ] {
    assert_eq(emit(text), "{\"current_timestamp\":[]}")
  }
  assert_true(
    lower(fixture("CURRENT_TIMESTAMP(1)"), _path => None, limits())
    is Err({ issue: InvalidArguments, .. }),
  )
  assert_true(
    lower(fixture("ACTQL.CURRENT_TIMESTAMP()"), _path => None, limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
}

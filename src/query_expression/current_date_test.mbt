///|
test "CURRENT_DATE SQL spellings preserve one zero-argument Common operation" {
  for
    text in ["CURRENT_DATE", "CURRENT_DATE()", "current_date", "(CURRENT_DATE)"] {
    assert_eq(emit(text), "{\"current_date\":[]}", msg=text)
  }
  assert_true(
    lower(fixture("CURRENT_DATE('UTC')"), _path => None, limits())
    is Err({ issue: InvalidArguments, .. }),
  )
  assert_true(
    lower(fixture("ACTQL.CURRENT_DATE()"), _path => None, limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
  for text in ["`CURRENT_DATE`", "t.CURRENT_DATE"] {
    let lowered = lower(fixture(text), _path => Some("name"), limits()).unwrap()
    let writer = @encode.writer(100000, 10000, 100)
    @expression.emit_source(expression(lowered), writer)
    assert_eq(@encode.finish(writer), "{\"field\":\"name\"}", msg=text)
  }
}

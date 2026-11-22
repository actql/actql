///|
fn extract_part_expression(part : String) -> @lower.Expression {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"clock\":{\"type\":\"timestamp\",\"nullable\":true}},\"rows\":[{\"clock\":null}]},\"as\":\"seed\"},{\"derive\":{\"field_part\":{\"extract_timestamp\":[{\"field\":\"clock\"},{\"literal\":\"" +
    part +
    "\"}]}}}]",
  )
  @lower.lower_expression(owner, 1, 0, {
    max_nodes: 100,
    max_work: 10000,
    max_depth: 100,
    max_literal_nodes: 100,
    max_literal_text_bytes: 1000,
  }).unwrap()
}

///|
test "extract_timestamp keeps UTC calendar and exact numeric Timestamp parts" {
  let leap = "2000-02-29T23:59:59.999999999Z"
  let before = "1969-12-31T23:59:59.123456789Z"
  for
    (value, part, expected) in [
      (leap, "year", 2000L),
      (leap, "quarter", 1L),
      (leap, "month", 2L),
      (leap, "day", 29L),
      (leap, "dayofweek", 3L),
      (leap, "dayofyear", 60L),
      (before, "quarter", 4L),
      (before, "dayofweek", 4L),
      (before, "dayofyear", 365L),
      (before, "hour", 23L),
      (before, "minute", 59L),
      (before, "second", 59L),
      (before, "millisecond", 123L),
      (before, "microsecond", 123456L),
    ] {
    let expression = extract_part_expression(part)
    let workspace = row_workspace(100)
    let original = difference_value("timestamp", value)
    let outcome = evaluate_expression_with_workspace(
      expression,
      Map([("clock", original)]),
      [],
      { remaining: 1000, max_frames: 10, },
      workspace,
    ).unwrap()
    assert_true(
      outcome is Captured(@admitted.Signed64(extracted)) &&
      extracted == expected,
      msg=value + " " + part,
    )
    assert_eq(workspace.live, 0)
  }
  let expression = extract_part_expression("year")
  assert_true(
    evaluate_expression(expression, Map([("clock", Null)]), [], {
      remaining: 1000,
      max_frames: 10,
    }).unwrap()
    is Null,
  )
  let writer = @encode.writer(10000, 100, 20)
  @lower.emit_expression(expression, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"body\":[{\"body\":\"clock\",\"op\":\"field\"},{\"body\":\"year\",\"op\":\"literal\"}],\"op\":\"extract_timestamp\"}",
  )
}

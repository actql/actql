///|
// The original source and complete machine oracle remain unchanged. Retain a
// typed lowering cause instead of hiding it behind Result::unwrap.
test "current event dedupe lowering reaches the independent common control" {
  let source = event_dedupe_source(
    "[]", "[{field: SCORE, dir: 'desc', nulls: 'last'}, {field: event_id, dir: 'asc', nulls: 'first'}]",
  )
  let actual = match
    with_carrier_program(source, { ..pair_context(), inputs: [], }) {
    Ok(program) => program
    Err(issue) =>
      fail("current event dedupe lowering: " + infer_defaults_issue_tag(issue))
  }
  let expected = event_dedupe_control(
    "[]", "[{\"field\":\"score\",\"dir\":\"desc\",\"nulls\":\"last\"},{\"field\":\"event_id\",\"dir\":\"asc\",\"nulls\":\"first\"}]",
  )
  assert_eq(
    with_carrier_argument(actual, "dedupe_events"),
    with_carrier_argument(expected, "dedupe_events"),
  )
  event_window_common_checked(actual)
}

///|
test "current event dedupe still rejects a genuinely insufficient common prefix allowance" {
  let source = event_dedupe_source("[]", "[{event_id: 'asc'}]")
  let query = @query.parse_query_script(source, syntax_limits()).unwrap()
  match
    compile_query_script(query, { ..pair_context(), inputs: [], }, {
      ..construction_limits(),
      max_expression_work: 1,
    }) {
    Err(Expression({ issue: @expression.WorkLimit, .. })) => ()
    Err(issue) =>
      fail(
        "expected original work refusal, got " + infer_defaults_issue_tag(issue),
      )
    Ok(_) => fail("cached Carrier cannot issue a fresh work allowance")
  }
}

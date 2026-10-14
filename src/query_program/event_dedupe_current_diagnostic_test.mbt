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

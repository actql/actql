///|
test "SQL current date and timestamp share a checked query invocation dependency" {
  let text = "WITH query_clock AS (SELECT CURRENT_TIMESTAMP() AS ts) SELECT CURRENT_DATE = CURRENT_DATE() AS same_day, CURRENT_DATE() = DATE(EXTRACT(YEAR FROM ts), EXTRACT(MONTH FROM ts), EXTRACT(DAY FROM ts)) AS same_original_utc_day FROM query_clock"
  let program = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"current_date\":[]"))
  assert_true(wire.contains("\"current_timestamp\":[]"))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("original query-time shape has no input references")
    Rejected(issue) => raise @check.diagnostic_cause(issue)
  }
}

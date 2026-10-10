///|
test "empty derived FROM PIVOT retains checked global count output" {
  let query = @query.parse_query(
    "SELECT * FROM (SELECT 1 AS sales,'A' AS axis WHERE FALSE) PIVOT(COUNT(sales) FOR axis IN('A'))",
    syntax_limits(),
  ).unwrap()
  let program = compile(
    query,
    { ..values_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(program).contains(
      "\"from\":\"aql_query_source_1\",\"select\":[\"A\"]",
    ),
  )
  match
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed empty derived source")
  }
}

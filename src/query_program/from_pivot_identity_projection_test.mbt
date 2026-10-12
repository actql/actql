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
  let wire = semantic(program)
  assert_eq(@program.stage_count(program), 1)
  assert_true(wire.contains("\"filter\":{\"literal\":false}"))
  assert_true(
    wire.contains(
      "\"pivot\":{\"aggregate\":\"count\",\"column\":\"axis\",\"index\":[],\"value\":\"sales\",\"values\":[\"A\"]}",
    ),
  )
  assert_true(wire.contains("\"select\":[\"A\"]"))
  assert_true(wire.contains("\"fields\":[\"A\"]"))
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

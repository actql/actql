///|
test "independent joined row objects use the existing checked object Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.join_row_ranges","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"left"},{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2}]},"as":"right"},{"from":"left","cross_join":{"with":"right","max_output_rows":10,"select":{"left_id":"left.id","right_id":"right.id"}},"as":"joined"},{"from":"joined","derive":{"left_row":{"object":{"id":{"field":"left_id"}}},"right_row":{"object":{"id":{"field":"right_id"}}}}},{"select":["left_row","right_row"],"as":"out"}],"results":{"rows":{"from":"out","fields":["left_row","right_row"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    _ => fail("closed joined object control")
  }
}

///|
test "joined ranges are row expressions in the public query script" {
  let query = @query.parse_query_script(
    "SELECT l AS left_row,r AS right_row FROM (SELECT 1 AS id) l CROSS JOIN (SELECT 2 AS id) r MAX_OUTPUT_ROWS 10",
    syntax_limits(),
  ).unwrap()
  let p = match
    compile_query_script(
      query,
      { ..values_context(), inputs: [], },
      construction_limits(),
    ) {
    Ok(p) => p
    Err(UnknownColumn) => fail("joined row: UnknownColumn")
    Err(Expression(issue)) =>
      fail("joined row expression: " + @debug.to_string(issue.issue))
    Err(UnsupportedProjection) => fail("joined row: UnsupportedProjection")
    Err(UnsupportedCte) => fail("joined row: UnsupportedCte")
    Err(_) => fail("joined row: other lowering refusal")
  }
  match @check.check_parsed(p, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    _ => fail("closed joined source")
  }
}

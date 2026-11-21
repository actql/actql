///|
test "GENERATE_ARRAY checks the original scalar and value-table entrances" {
  for
    text in [
      "SELECT GENERATE_ARRAY(1, 3) AS x", "FROM UNNEST(GENERATE_ARRAY(1, 3)) AS x",
      "WITH p AS (SELECT 5 AS lo, 1 AS hi) SELECT GENERATE_ARRAY(lo, hi, -2) AS x FROM p",
      "WITH p AS (SELECT 5 AS lo, 1 AS hi) SELECT x FROM p CROSS JOIN UNNEST(GENERATE_ARRAY(lo, hi, -2)) AS x",
      "SELECT GENERATE_ARRAY(9223372036854775806, 9223372036854775807) AS x",
    ] {
    let parsed = match @query.parse_query(text, syntax_limits()) {
      Ok(parsed) => parsed
      Err(issue) => fail(text + ": " + @debug.to_string(issue.issue))
    }
    let program = match
      compile(
        parsed,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Ok(program) => program
      Err(Expression(issue)) =>
        fail(text + ": " + @debug.to_string(issue.issue))
      Err(ExpressionTyping(issue)) =>
        fail(text + ": " + @debug.to_string(issue.kind))
      Err(UnsupportedJoin) => fail(text + ": UnsupportedJoin")
      Err(UnsupportedProjection) => fail(text + ": UnsupportedProjection")
      Err(UnresolvedRelation(_)) => fail(text + ": UnresolvedRelation")
      Err(UnknownColumn) => fail(text + ": UnknownColumn")
      Err(_) => fail(text + ": failed to compile")
    }
    assert_true(semantic(program).contains("\"generate_array\""), msg=text)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("these progressions use only authored Values")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

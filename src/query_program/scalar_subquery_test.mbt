///|
test "scalar subquery projects one independently checked column" {
  for
    source in [
      "SELECT (SELECT 1) AS x", "WITH t AS (SELECT 10 AS v UNION ALL SELECT 30 AS v) SELECT (SELECT MAX(v) FROM t) AS x",
      "SELECT (SELECT 'value' WHERE FALSE) AS x", "SELECT (SELECT 10 UNION ALL SELECT 30) AS x",
    ] {
    let query = @query.parse_query(source, syntax_limits()).unwrap()
    assert_eq(@query.scalar_projection_count(query), 1, msg=source)
    let program = compile(
      query,
      { ..fixture_context(), inputs: [], captured_stage: Some("capture"), },
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail(source)
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
    let wire = semantic(program)
    assert_true(wire.contains("\"fields\":[\"x\"]"), msg=source)
    assert_true(wire.contains("\"assert_rows\""), msg=source)
  }
}

///|
test "scalar subquery rejects multiple columns and retains anonymous output" {
  let context = { ..fixture_context(), inputs: [], }
  assert_true(
    compile(
      @query.parse_query("SELECT (SELECT 1 AS a, 2 AS b) AS x", syntax_limits()).unwrap(),
      context,
      construction_limits(),
    )
    is Err(UnsupportedProjection),
  )
  let program = compile(
    @query.parse_query("SELECT (SELECT 1)", syntax_limits()).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  assert_true(semantic(program).contains("\"fields\":[\"f0_\"]"))
}

///|
test "scalar projection demand comes from the original selected subqueries" {
  let nested = @query.parse_query(
    "SELECT (SELECT (SELECT 1) AS nested_value) AS value",
    syntax_limits(),
  ).unwrap()
  assert_eq(@query.scalar_projection_count(nested), 2)
  let text = @query.parse_query(
    "SELECT 'SELECT (SELECT 1)' AS value",
    syntax_limits(),
  ).unwrap()
  assert_eq(@query.scalar_projection_count(text), 0)
}

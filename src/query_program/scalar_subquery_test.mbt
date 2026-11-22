///|
test "scalar subquery projects one independently checked column" {
  for
    (source, needs_assertion) in [
      ("SELECT (SELECT 1) AS x", true),
      (
        "WITH t AS (SELECT 1 AS n, 'a' AS s, 10 AS v UNION ALL SELECT 2 AS n, 'b' AS s, 20 AS v UNION ALL SELECT 3 AS n, 'a' AS s, 30 AS v) SELECT (SELECT MAX(v) FROM t) AS x",
        false,
      ),
      (
        "WITH t AS (SELECT 10 AS v) SELECT (SELECT MIN(v) AS child FROM t WHERE v < 0) AS x",
        false,
      ),
      (
        "WITH t AS (SELECT 10 AS v) SELECT (SELECT MAX(v) AS child FROM t HAVING child > 100) AS x",
        true,
      ),
      ("WITH t AS (SELECT 10 AS v) SELECT (SELECT COUNT(*) FROM t) AS x", true),
      ("SELECT (SELECT 'value' WHERE FALSE) AS x", true),
      ("SELECT (SELECT 10 UNION ALL SELECT 30) AS x", true),
    ] {
    let query = @query.parse_query(source, syntax_limits()).unwrap()
    assert_eq(@query.scalar_projection_count(query), 1, msg=source)
    let program = compile(
      query,
      { ..fixture_context(), inputs: [], captured_stage: Some("capture"), },
      construction_limits(),
    ).unwrap()
    let checked = match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(checked) => checked
      NeedsInputs(_) => fail(source)
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
    let wire = semantic(program)
    assert_true(wire.contains("\"fields\":[\"x\"]"), msg=source)
    assert_eq(wire.contains("\"assert_rows\""), needs_assertion, msg=source)
    if !needs_assertion {
      assert_false(wire.contains("\"any_value\""), msg=source)
      let results = @stage_results.stage_at(
        @check.checked_stage_results(checked),
        0,
      ).unwrap()
      let result = @relation_results.lookup(results, "rows").unwrap()
      let schema = @relation_results.output_schema(result)
      let contract = @schema.lookup(schema, Unqualified("x")).unwrap()
      assert_eq(@relation_results.fields(result), ["x"], msg=source)
      assert_eq(@schema.field_count(schema), 1, msg=source)
      assert_true(contract.nullable && contract.shape is Number, msg=source)
    }
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

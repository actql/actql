///|
test "DATA CTE SQL and Pipe bodies preserve one logical producer" {
  // Authored directly from Values and producer-reference contracts. A CTE
  // inside DATA does not add a capture, Stage Result or physical placement.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_2"},{"from":"aql_script_seed_2","derive":{"aql_query_expr_0":{"literal":2}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_script_cte_1"},{"from":"aql_script_cte_1","select":["id"],"as":"aql_data_0"},{"from":"aql_data_0","select":["id"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    text in [
      "DATA copied = WITH first AS (SELECT 2 AS id) SELECT id FROM first; FROM copied |> SELECT id",
      "DATA copied = WITH first AS (SELECT 2 AS id) FROM first |> SELECT id; FROM copied |> SELECT id",
    ] {
    let program = compile_query_script(
      @query.parse_query_script(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(expected))
    assert_eq(@program.stage_count(program), 1)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      _ => fail("the logical CTE producer is already declared")
    }
  }
}

///|
test "DATA CTEs reuse a retained capture through nested and set queries" {
  for
    text in [
      "DATA copied = WITH first AS (FROM orders |> WHERE amount > 10 |> SELECT id), second AS (FROM first |> SELECT id) FROM second |> SELECT id; FROM copied |> SELECT id",
      "DATA copied = WITH chosen AS (WITH hidden AS (FROM orders |> SELECT id) FROM hidden |> SELECT id) FROM chosen |> SELECT id; FROM copied |> SELECT id",
      "DATA copied = WITH chosen AS (FROM orders |> SELECT id) SELECT id FROM chosen UNION ALL SELECT id FROM chosen; FROM copied |> SELECT id",
    ] {
    let program = compile_query_script(
      @query.parse_query_script(text, syntax_limits()).unwrap(),
      { ..fixture_context(), captured_stage: Some("capture"), },
      construction_limits(),
    ).unwrap()
    assert_eq(@program.stage_count(program), 2)
    assert_eq(@program.export_count(program), 1)
    let body = semantic(program)
    assert_eq(body.split("\"carrier\":\"relation\"").length(), 2)
    assert_eq(body.split("\"stage\":\"capture\"").length(), 2)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      _ => fail("a CTE reference does not request another capture")
    }
  }
}

///|
test "DATA CTE scope quotes aliases and does not export them into later DATA" {
  let valid = compile_query_script(
    @query.parse_query_script(
      "DATA original = SELECT 2 AS id; DATA copied = WITH chosen AS (FROM `ORIGINAL` |> SELECT id) FROM `CHOSEN` |> SELECT id; FROM copied |> SELECT id",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_eq(@program.stage_count(valid), 1)
  assert_eq(semantic(valid).split("\"values\":").length(), 2)
  match @check.check_parsed(valid, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("quoted DATA/CTE aliases use their existing alias rules")
  }
  for
    text in [
      "DATA copied = WITH chosen AS (SELECT 2 AS id) FROM chosen |> SELECT id; FROM chosen |> SELECT id",
      "DATA copied = WITH chosen AS (FROM later |> SELECT id), later AS (SELECT 2 AS id) FROM chosen |> SELECT id; FROM copied |> SELECT id",
      "DATA copied = WITH chosen AS (FROM chosen |> SELECT id) FROM chosen |> SELECT id; FROM copied |> SELECT id",
      "DATA copied = WITH chosen AS (FROM orders |> SELECT id) FROM chosen |> SELECT amount; FROM copied |> SELECT id",
    ] {
    assert_true(
      compile_query_script(
        @query.parse_query_script(text, syntax_limits()).unwrap(),
        fixture_context(),
        construction_limits(),
      )
      is Err(_),
      msg=text,
    )
  }
}

///|
test "nonrecursive CTE body binds an existing outer producer before its alias" {
  let query = @query.parse_query(
    "WITH orders AS (SELECT id FROM orders) SELECT id FROM orders",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, fixture_context(), construction_limits()).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("outer source admission and CTE binding remain distinct")
  }
  let script = @query.parse_query_script(
    "DATA copied = WITH orders AS (FROM orders |> SELECT id) FROM orders |> SELECT id; FROM copied |> SELECT id",
    syntax_limits(),
  ).unwrap()
  let data = compile_query_script(
    script,
    fixture_context(),
    construction_limits(),
  ).unwrap()
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{"orders":{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"orders","select":["id"],"as":"aql_script_cte_2"},{"from":"aql_script_cte_2","select":["id"],"as":"aql_data_1"},{"from":"aql_data_1","select":["id"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(data), semantic(expected))
  assert_eq(@program.stage_count(data), 1)
  match @check.check_parsed(data, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("the outer producer is not a recursive CTE binding")
  }
}

///|
test "DATA CTE composition retains syntax and Program budgets" {
  let text = "DATA copied = WITH first AS (SELECT 2 AS id), second AS (FROM first |> SELECT id) FROM second |> SELECT id; FROM copied |> SELECT id"
  assert_true(
    @query.parse_query_script(text, { ..syntax_limits(), max_cte_count: 1, })
    is Err(_),
  )
  let script = @query.parse_query_script(text, syntax_limits()).unwrap()
  assert_true(
    compile_query_script(script, { ..fixture_context(), inputs: [], }, {
      ..construction_limits(),
      program: {
        ..construction_limits().program,
        tree: { ..construction_limits().program.tree, max_nodes: 5, },
      },
    })
    is Err(Admission(_)),
  )
}

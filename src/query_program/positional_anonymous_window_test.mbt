///|
test "anonymous terminal positional windows keep their ordinal values" {
  // The right input x=1 gives (1,2), x=2 gives (2,1). No output alias
  // is authored for either window; a/b come from the left operand.
  let source = "WITH r AS (SELECT 1 AS x UNION ALL SELECT 2 AS x) SELECT 0 AS a, 0 AS b UNION ALL SELECT ROW_NUMBER() OVER (ORDER BY x), ROW_NUMBER() OVER (ORDER BY x DESC) FROM r ORDER BY a, b"
  let query = @query.parse_query_script(source, syntax_limits()).unwrap()
  let actual = compile_query_script(
    query,
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the anonymous window input is local Values")
  }
}

///|
test "anonymous window independent JSON control has named public fields" {
  // This normal Program is hand-authored. Its independent expected output
  // is (0,0), (1,2), (2,1), both fields nonnullable numbers.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.anonymous_windows","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1},{"x":2}]},"as":"input"},{"from":"input","analytic":{"partition_by":[],"order_by":[{"field":"x","dir":"asc","nulls":"first"}],"functions":{"up":{"fn":"row_number"}}}},{"analytic":{"partition_by":[],"order_by":[{"field":"x","dir":"desc","nulls":"last"}],"functions":{"down":{"fn":"row_number"}}}},{"select":[{"a":"up"},{"b":"down"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false},"b":{"type":"number","nullable":false}},"rows":[{"a":0,"b":0}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"},{"field":"b","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the independent window control has no acquisition")
  }
}

///|
test "anonymous windows preserve scoped input and typed empty outputs" {
  for
    source in [
      "WITH r AS (SELECT 1 AS x UNION ALL SELECT 2 AS x) SELECT 0 AS a, 0 AS b |> UNION ALL (FROM r |> AS original |> SET x = -x |> SELECT ROW_NUMBER() OVER (ORDER BY original.x), ROW_NUMBER() OVER (ORDER BY x)) |> ORDER BY a, b",
      "WITH r AS (SELECT 1 AS x UNION ALL SELECT 2 AS x) SELECT 0 AS a, 0 AS b UNION ALL SELECT ROW_NUMBER() OVER (ORDER BY x), ROW_NUMBER() OVER (ORDER BY x DESC) AS n FROM r QUALIFY n > 0 ORDER BY a, b",
      "WITH r AS (SELECT 1 AS x WHERE FALSE) SELECT 0 AS a, 0 AS b WHERE FALSE UNION ALL SELECT ROW_NUMBER() OVER (ORDER BY x), ROW_NUMBER() OVER (ORDER BY x DESC) FROM r ORDER BY a, b",
    ] {
    let actual = match
      compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
      Err(UnsupportedAnalytic) => fail(source + ": UnsupportedAnalytic")
      Err(UnsupportedOrdering) => fail(source + ": UnsupportedOrdering")
      Err(Construction(cause)) => fail(source + ": " + @debug.to_string(cause))
      Err(Expression(_)) => fail(source + ": Expression")
      Err(_) => fail(source + ": another refusal")
    }
    match
      @check.check_parsed(
        actual,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("the window controls have no acquisition")
    }
  }
}

///|
test "anonymous windows never add public or authored private aliases" {
  for
    source in [
      "WITH r AS (SELECT 1 AS x) SELECT ROW_NUMBER() OVER (ORDER BY x) FROM r", "WITH r AS (SELECT 1 AS x) SELECT 0 AS a UNION ALL BY NAME SELECT ROW_NUMBER() OVER (ORDER BY x) FROM r",
      "WITH r AS (SELECT 1 AS x) FROM r |> SELECT ROW_NUMBER() OVER (ORDER BY x) |> WHERE TRUE",
    ] {
    assert_true(
      compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(UnsupportedProjection),
      msg=source,
    )
  }
  let head = "WITH r AS (SELECT 1 AS x) SELECT 0 AS a, 0 AS b UNION ALL SELECT ROW_NUMBER() OVER (ORDER BY x), ROW_NUMBER() OVER (ORDER BY x DESC) FROM r QUALIFY "
  for field in ["aql_analytic_output_1", "aql_set_anonymous_3"] {
    match
      compile_query_script(
        @query.parse_query_script(head + field + " > 0", syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Err(Expression({ issue: @expression.UnknownReference, .. })) => ()
      Ok(_) => fail("the anonymous output acquired an authored receiver")
      Err(_) => fail("the private receiver failed for another reason")
    }
  }
}

///|
test "anonymous window lowering matches the independent complete WITH Program" {
  // Slots are predicted from the declared input and ordinal projection;
  // the expected Program is never serialized from a frontend compilation.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_2"},{"from":"aql_script_seed_2","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"x":"aql_query_expr_0"}],"as":"aql_data_set_term_1"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_4"},{"from":"aql_script_seed_4","derive":{"aql_query_expr_0":{"literal":2}}},{"select":[{"x":"aql_query_expr_0"}],"as":"aql_data_set_term_3"},{"from":"aql_data_set_term_1","append":{"with":"aql_data_set_term_3"},"as":"aql_script_cte_0"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_8"},{"from":"aql_script_seed_8","derive":{"aql_query_expr_0":{"literal":0},"aql_query_expr_1":{"literal":0}}},{"select":[{"a":"aql_query_expr_0"},{"b":"aql_query_expr_1"}],"as":"aql_data_set_term_7"},{"from":"aql_script_cte_0","analytic":{"partition_by":[],"order_by":[{"field":"x","dir":"asc","nulls":"first"}],"functions":{"aql_analytic_output_1":{"fn":"row_number"}}}},{"analytic":{"partition_by":[],"order_by":[{"field":"x","dir":"desc","nulls":"last"}],"functions":{"aql_analytic_output_2":{"fn":"row_number"}}}},{"select":[{"a":"aql_analytic_output_1"},{"b":"aql_analytic_output_2"}],"as":"aql_data_set_term_9"},{"from":"aql_data_set_term_7","append":{"with":"aql_data_set_term_9"},"as":"aql_script_cte_6"},{"from":"aql_script_cte_6","select":["a","b"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile_with_set(
    "WITH r AS (SELECT 1 AS x UNION ALL SELECT 2 AS x), e AS (SELECT 0 AS a, 0 AS b UNION ALL SELECT ROW_NUMBER() OVER (ORDER BY x), ROW_NUMBER() OVER (ORDER BY x DESC) FROM r) FROM e |> SELECT a, b",
  )
  assert_eq(semantic(actual), semantic(expected))
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) =>
      fail("the independent complete Program has no acquisition")
  }
}

///|
test "FULL explicit CTE projection matches an independent complete Program" {
  // This fixture declares both input key premises and every value/port/order.
  // It uses the ordinary join and SELECT contracts, not frontend execution.
  let staged_control = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"aql_cte_0","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","assert_rows":{"unique_by":["x"]},"as":"aql_cte_final"}],"results":{"rows":{"from":"aql_cte_final","fields":["x","y"]}}},{"id":"main","inputs":{"aql_chain_input_0":{"result":{"stage":"aql_cte_0","result":"rows"}},"aql_chain_input_1":{"result":{"stage":"aql_cte_0","result":"rows"}}},"steps":[{"from":"aql_chain_input_0","join":{"with":"aql_chain_input_1","kind":"full","on":[{"left":"x","right":"x"}],"max_output_rows":10,"select":{"aql_chain_column_2":"left.x","aql_chain_column_3":"left.y","aql_chain_column_4":"right.x","aql_chain_column_5":"right.y"}},"as":"aql_chain_join_2"},{"from":"aql_chain_join_2","sort":[{"field":"aql_chain_column_4","dir":"asc","nulls":"last"}]},{"select":[{"x":"aql_chain_column_2"},{"y":"aql_chain_column_3"},{"k":"aql_chain_column_4"}],"as":"aql_chain_result_3"}],"results":{"rows":{"from":"aql_chain_result_3","fields":["x","y","k"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(
      staged_control,
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent keyed FULL Program must be checked")
  }
  // The unified WITH owner uses one shared producer in the main Stage.
  // The earlier staged Program remains a separate checked contract control.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"aql_script_seed_3"},{"from":"aql_script_seed_3","assert_rows":{"unique_by":["x"]},"as":"aql_script_cte_2"},{"from":"aql_script_cte_2","join":{"with":"aql_script_cte_2","kind":"full","on":[{"left":"x","right":"x"}],"max_output_rows":10,"select":{"aql_chain_column_2":"left.x","aql_chain_column_3":"left.y","aql_chain_column_4":"right.x","aql_chain_column_5":"right.y"}},"as":"aql_chain_join_4"},{"from":"aql_chain_join_4","sort":[{"field":"aql_chain_column_4","dir":"asc","nulls":"last"}]},{"select":[{"x":"aql_chain_column_2"},{"y":"aql_chain_column_3"},{"k":"aql_chain_column_4"}],"as":"aql_chain_result_5"}],"results":{"rows":{"from":"aql_chain_result_5","fields":["x","y","k"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent unified WITH FULL Program must be checked")
  }
  let actual = compile(
    @query.parse_query(
      "WITH keyed AS (FROM t |> ASSERT UNIQUE BY (x)) SELECT l.x AS x, l.y AS y, r.x AS k FROM keyed AS l FULL JOIN keyed AS r ON l.x = r.x MAX_OUTPUT_ROWS 10 ORDER BY k NULLS LAST",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("explicit FULL CTE projection must retain checked key premises")
  }
}

///|
test "FULL explicit SELECT preserves keyed WITH inputs and ordered fields" {
  let prefix = "WITH lefts AS (FROM t |> ASSERT UNIQUE BY (x)), rights AS (FROM r |> ASSERT UNIQUE BY (k)) "
  for
    body in [
      "SELECT t.x, t.y, r.k FROM lefts AS t FULL JOIN rights AS r ON t.x = r.k MAX_OUTPUT_ROWS 10 ORDER BY k NULLS LAST",
      "FROM lefts AS t |> FULL JOIN rights AS r ON t.x = r.k MAX_OUTPUT_ROWS 10 |> SELECT t.x, t.y, r.k |> ORDER BY k NULLS LAST",
      "SELECT DISTINCT t.x, t.y, r.k FROM lefts AS t FULL JOIN rights AS r ON t.x = r.k MAX_OUTPUT_ROWS 10 ORDER BY k NULLS LAST",
    ] {
    let generated = compile_query_script(
      @query.parse_query_script(prefix + body, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(generated, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("explicit FULL projection must retain the checked WITH keys")
    }
    let body = semantic(generated)
    assert_true(body.contains("\"kind\":\"full\""))
    assert_true(body.contains("\"max_output_rows\":10"))
    assert_true(body.contains("\"unique_by\":[\"x\"]"))
    assert_true(body.contains("\"unique_by\":[\"k\"]"))
    assert_true(body.contains("\"fields\":[\"x\",\"y\",\"k\"]"))
    assert_false(body.contains("\"fields\":[\"aql_chain_column_"))
  }
}

///|
test "unkeyed FULL explicit SELECT reaches the common identity refusal" {
  for distinct in ["", "DISTINCT "] {
    let generated = compile(
      @query.parse_query(
        "SELECT " +
        distinct +
        "t.x, r.k FROM t FULL JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 10 ORDER BY t.x NULLS LAST",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(generated, check_environment(), None, check_limits()) {
      Rejected(error) =>
        assert_true(
          @check.diagnostic_cause(error)
          is Closure(Joins(MissingStableIdentity(_))),
        )
      _ => fail("explicit FULL projection cannot manufacture row identity")
    }
  }
}

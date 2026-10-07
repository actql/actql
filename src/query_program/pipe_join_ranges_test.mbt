///|
test "Pipe JOIN preserves SET DROP and RENAME range snapshots through the checker" {
  for
    (prefix, projection) in [
      ("SET x = x + 10", "x AS current, l.x AS original, rr.k AS matched"),
      ("DROP x", "y AS current, l.x AS original, rr.k AS matched"),
      ("RENAME x AS current", "current, l.x AS original, rr.k AS matched"),
    ] {
    let text = "FROM t |> AS l |> " +
      prefix +
      " |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> SELECT " +
      projection +
      " |> ORDER BY original"
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    for
      program in [
        compile(query, join_order_context(), construction_limits()).unwrap(),
        compile_query_script(
          @query.single_query_script(query),
          join_order_context(),
          construction_limits(),
        ).unwrap(),
      ] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        Rejected(error) => raise @check.diagnostic_cause(error)
        _ => fail("closed range snapshots must not introduce acquisition")
      }
    }
  }
}

///|
test "Pipe JOIN remaps evaluated slots rather than rebinding original values" {
  // Full independent existing Program: SET derives another slot, ON uses x,
  // and the output carries both that original and the evaluated replacement.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":10}}},{"select":[{"x":"aql_query_expr_0"},{"y":"aql_query_expr_1"}],"as":"aql_data_0"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_3"},{"from":"aql_script_seed_3","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"k":"aql_query_expr_0"}],"as":"aql_data_2"},{"from":"aql_data_0","derive":{"aql_pipe_set_2":{"add":[{"field":"x"},{"literal":10}]}},"as":"aql_script_cte_5"},{"from":"aql_script_cte_5","join":{"with":"aql_data_2","max_output_rows":10,"select":{"aql_chain_column_3":"left.x","aql_chain_column_4":"left.y","aql_chain_column_5":"left.aql_pipe_set_2","aql_chain_column_6":"right.k"},"kind":"inner","on":[{"left":"x","right":"k"}]},"as":"aql_chain_join_6"},{"from":"aql_chain_join_6","select":[{"current":"aql_chain_column_5"},{"original":"aql_chain_column_3"},{"matched":"aql_chain_column_6"}],"as":"aql_chain_result_7"},{"from":"aql_chain_result_7","select":["current","original","matched"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["current","original","matched"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = checked_data_join(
    "DATA lefts = SELECT 1 AS x, 10 AS y; DATA rights = SELECT 1 AS k; DATA paired = FROM lefts |> AS l |> SET x = x + 10 |> JOIN rights AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> SELECT x AS current, l.x AS original, rr.k AS matched; FROM paired |> SELECT current, original, matched",
    { ..fixture_context(), inputs: [], },
  )
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "Pipe JOIN carries several ranges and refuses removed current names" {
  let query = @query.parse_query(
    "FROM t AS l |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> SET x = x + 10 |> JOIN r AS s ON l.x = s.k MAX_OUTPUT_ROWS 10 |> SELECT x AS current, l.x AS original, rr.k AS first, s.k AS second",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, join_order_context(), construction_limits()).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("range continuation remains closed")
  }
  for prefix in ["DROP x", "RENAME x AS current"] {
    assert_true(
      compile(
        @query.parse_query(
          "FROM t |> AS l |> " +
          prefix +
          " |> JOIN r AS rr ON x = rr.k |> SELECT l.x",
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(AmbiguousColumn),
    )
  }
}

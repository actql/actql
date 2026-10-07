///|
test "FULL USING scope agrees with a complete independent coalesced Program" {
  // Declared assertions supply conditional identity, not sample-row inference.
  // USING merges one public key while retaining both qualified value slots.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"aql_cte_0","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","assert_rows":{"unique_by":["x"]},"as":"aql_cte_final"}],"results":{"rows":{"from":"aql_cte_final","fields":["x","y"]}}},{"id":"main","inputs":{"aql_chain_input_0":{"result":{"stage":"aql_cte_0","result":"rows"}},"aql_chain_input_1":{"result":{"stage":"aql_cte_0","result":"rows"}}},"steps":[{"from":"aql_chain_input_0","join":{"with":"aql_chain_input_1","kind":"full","on":[{"left":"x","right":"x"}],"max_output_rows":10,"select":{"aql_chain_column_2":"left.x","aql_chain_column_3":"left.y","aql_chain_column_4":"right.x","aql_chain_column_5":"right.y"}},"as":"aql_chain_join_2"},{"from":"aql_chain_join_2","derive":{"aql_chain_column_6":{"coalesce":[{"field":"aql_chain_column_2"},{"field":"aql_chain_column_4"}]}},"as":"aql_chain_merged_3"},{"from":"aql_chain_merged_3","sort":[{"field":"aql_chain_column_6","dir":"asc","nulls":"first"}]},{"select":[{"x":"aql_chain_column_6"},{"a":"aql_chain_column_3"},{"b":"aql_chain_column_5"}],"as":"aql_chain_result_4"}],"results":{"rows":{"from":"aql_chain_result_4","fields":["x","a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent FULL USING Program must preserve checked identity")
  }
  let query = @query.parse_query(
    "WITH keyed AS (FROM t |> ASSERT UNIQUE BY (x)) SELECT * EXCEPT (y), l.y AS a, r.y AS b FROM keyed AS l FULL JOIN keyed AS r USING (x) MAX_OUTPUT_ROWS 10 ORDER BY x",
    syntax_limits(),
  ).unwrap()
  let generated = match
    compile(query, join_order_context(), construction_limits()) {
    Ok(program) => program
    Err(UnsupportedJoin) =>
      fail("Frontend rejected the checked FULL USING row scope")
    Err(_) => fail("unexpected FULL USING lowering failure")
  }
  assert_eq(semantic(generated), semantic(expected))
  match
    @check.check_parsed(generated, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("FULL USING must retain the admitted key obligations")
  }
}

///|
test "FULL USING keeps authored composite order and original qualified keys" {
  let generated = compile(
    @query.parse_query(
      "WITH keyed AS (FROM t |> ASSERT UNIQUE BY (x)) SELECT *, l.x AS original, r.x AS preserved FROM keyed AS l FULL JOIN keyed AS r USING (`Y`, x) MAX_OUTPUT_ROWS 10 ORDER BY x",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(generated)
  assert_true(
    wire.contains("\"fields\":[\"y\",\"x\",\"original\",\"preserved\"]"),
  )
  assert_true(
    wire.contains(
      "\"coalesce\":[{\"field\":\"aql_chain_column_3\"},{\"field\":\"aql_chain_column_5\"}]",
    ),
  )
  assert_true(
    wire.contains(
      "\"coalesce\":[{\"field\":\"aql_chain_column_2\"},{\"field\":\"aql_chain_column_4\"}]",
    ),
  )
  assert_true(wire.contains("{\"original\":\"aql_chain_column_2\"}"))
  assert_true(wire.contains("{\"preserved\":\"aql_chain_column_4\"}"))
  assert_true(
    @check.check_parsed(generated, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "later USING joins read the merged current key without replacing old ranges" {
  let generated = compile(
    @query.parse_query(
      "WITH keyed AS (FROM t |> ASSERT UNIQUE BY (x)) SELECT x, l.x AS original, r.x AS preserved FROM keyed AS l FULL JOIN keyed AS r USING (x) MAX_OUTPUT_ROWS 10 JOIN keyed AS s USING (x) MAX_OUTPUT_ROWS 10 ORDER BY x",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(generated)
  assert_true(
    wire.contains("\"on\":[{\"left\":\"aql_chain_column_6\",\"right\":\"x\"}]"),
  )
  assert_true(wire.contains("{\"original\":\"aql_chain_column_2\"}"))
  assert_true(wire.contains("{\"preserved\":\"aql_chain_column_4\"}"))
  assert_true(
    @check.check_parsed(generated, check_environment(), None, check_limits())
    is Checked(_),
  )
}

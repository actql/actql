///|
test "JOIN chain resolves every previous range and output alias" {
  for
    body in [
      "SELECT l.x AS y FROM seed AS l JOIN seed AS r ON l.x = r.x JOIN seed AS s ON r.x = s.x ORDER BY y + 1",
      "FROM seed AS l |> JOIN seed AS r ON l.x = r.x |> JOIN seed AS s ON r.x = s.x |> SELECT l.x AS y |> ORDER BY y + 1",
      "SELECT l.x AS y FROM seed AS l JOIN seed AS r ON l.x = r.x JOIN seed AS s ON l.x = s.x ORDER BY r.y + 1",
    ] {
    let program = checked_data_join(
      "DATA seed = FROM t |> SELECT x, y; DATA joined = " +
      body +
      "; FROM joined |> SELECT y",
      join_order_context(),
    )
    let wire = semantic(program)
    assert_eq(@program.stage_count(program), 1)
    assert_eq(wire.split("\"join\":").length(), 3)
    assert_true(wire.contains("\"fields\":[\"y\"]"))
    assert_eq(wire.split("\"add\":").length(), 2)
  }
}

///|
test "JOIN chain USING merges only unqualified key visibility" {
  let program = checked_data_join(
    "DATA seed = FROM t |> SELECT x, y; SELECT x, l.y AS a, r.y AS b, s.y AS c FROM seed AS l JOIN seed AS r USING (x) JOIN seed AS s USING (x)",
    join_order_context(),
  )
  assert_true(
    semantic(program).contains("\"fields\":[\"x\",\"a\",\"b\",\"c\"]"),
  )
}

///|
test "JOIN chain rejects ambiguous and out of scope keys" {
  for
    suffix in [
      "SELECT x FROM seed AS l JOIN seed AS r ON l.x = r.x JOIN seed AS s ON r.x = s.x",
      "SELECT l.x FROM seed AS l JOIN seed AS r ON s.x = r.x JOIN seed AS s ON l.x = s.x",
      "SELECT l.x FROM seed AS l JOIN seed AS r ON l.x = r.x JOIN seed AS r ON l.x = r.x",
      "SELECT l.x FROM seed AS l JOIN seed AS r ON l.x = r.x JOIN seed AS s ON l.x > s.x",
    ] {
    assert_true(
      compile_query_script(
        @query.parse_query_script(
          "DATA seed = FROM t |> SELECT x, y; " + suffix,
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(_),
      msg=suffix,
    )
  }
}

///|
test "standalone and CTE JOIN chains use the shared column scope" {
  for
    text in [
      "SELECT l.x AS y FROM t AS l JOIN t AS r ON l.x = r.x JOIN t AS s ON r.x = s.x ORDER BY y + 1",
      "WITH a AS (SELECT x, y FROM t), b AS (SELECT x, y FROM t), c AS (SELECT x, y FROM t) SELECT a.x AS y FROM a JOIN b ON a.x = b.x JOIN c ON b.x = c.x ORDER BY y + 1",
      "WITH a AS (SELECT x, y FROM t), joined AS (SELECT l.x AS y FROM a AS l JOIN a AS r ON l.x = r.x JOIN a AS s ON r.x = s.x) SELECT y FROM joined ORDER BY y + 1",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("JOIN chain inputs must be closed")
    }
    assert_eq(semantic(program).split("\"join\":").length(), 3)
    assert_true(semantic(program).contains("\"fields\":[\"y\"]"))
  }
}

///|
test "JOIN chain Program agrees with an independent existing-IR fixture" {
  // Authored from select/join/sort contracts, not copied from lowerer output.
  // All three ranges reference one Values producer. Only output y is public.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"aql_chain_source_0","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"}],"results":{"aql_chain_source_0":{"from":"t","fields":["x","y"]}}},{"id":"main","inputs":{"aql_chain_input_0":{"result":{"stage":"aql_chain_source_0","result":"aql_chain_source_0"}},"aql_chain_input_1":{"result":{"stage":"aql_chain_source_0","result":"aql_chain_source_0"}},"aql_chain_input_2":{"result":{"stage":"aql_chain_source_0","result":"aql_chain_source_0"}}},"steps":[{"from":"aql_chain_input_0","join":{"with":"aql_chain_input_1","kind":"inner","on":[{"left":"x","right":"x"}],"max_output_rows":1000,"select":{"aql_chain_column_2":"left.x","aql_chain_column_3":"left.y","aql_chain_column_4":"right.x","aql_chain_column_5":"right.y"}},"as":"aql_chain_join_3"},{"from":"aql_chain_join_3","join":{"with":"aql_chain_input_2","kind":"inner","on":[{"left":"aql_chain_column_4","right":"x"}],"max_output_rows":1000,"select":{"aql_chain_column_2":"left.aql_chain_column_2","aql_chain_column_3":"left.aql_chain_column_3","aql_chain_column_4":"left.aql_chain_column_4","aql_chain_column_5":"left.aql_chain_column_5","aql_chain_column_6":"right.x","aql_chain_column_7":"right.y"}},"as":"aql_chain_join_4"},{"from":"aql_chain_join_4","derive":{"aql_pipe_sort_7":{"add":[{"field":"aql_chain_column_2"},{"literal":1}]}}},{"sort":[{"field":"aql_pipe_sort_7","dir":"asc","nulls":"first"}]},{"select":[{"y":"aql_chain_column_2"}],"as":"aql_chain_result_5"}],"results":{"rows":{"from":"aql_chain_result_5","fields":["y"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let generated = compile(
    @query.parse_query(
      "SELECT l.x AS y FROM t AS l JOIN t AS r ON l.x = r.x JOIN t AS s ON r.x = s.x ORDER BY y + 1",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(generated), semantic(expected))
  // Renaming is part of the JOIN projection, not an extra materialization.
  assert_false(semantic(generated).contains("aql_chain_seed_"))
}

///|
test "JOIN chain preserves shared CTE capture and rejected resource ceilings" {
  let program = checked_data_join(
    "DATA joined = WITH seed AS (FROM orders |> SELECT id) SELECT l.id FROM seed AS l JOIN seed AS r ON l.id = r.id JOIN seed AS s ON r.id = s.id; FROM joined |> SELECT id",
    { ..fixture_context(), captured_stage: Some("capture"), },
  )
  assert_eq(@program.stage_count(program), 2)
  assert_eq(semantic(program).split("\"stage\":\"capture\"").length(), 2)
  let query = @query.parse_query(
    "SELECT l.x FROM t AS l CROSS JOIN t AS r CROSS JOIN t AS s",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, join_order_context(), {
      ..construction_limits(),
      max_join_output_rows: 7L,
    })
    is Err(UnsupportedJoin),
  )
}

///|
test "JOIN chain DISTINCT reuses the selected expression after projection" {
  let program = checked_data_join(
    "DATA seed = FROM t |> SELECT x, y; SELECT DISTINCT l.x AS out FROM seed AS l JOIN seed AS m ON l.x = m.x JOIN seed AS r ON m.x = r.x ORDER BY l.x",
    join_order_context(),
  )
  assert_true(semantic(program).contains("\"field\":\"out\""))
  assert_true(
    compile_query_script(
      @query.parse_query_script(
        "DATA seed = FROM t |> SELECT x, y; SELECT DISTINCT l.x AS out FROM seed AS l JOIN seed AS m ON l.x = m.x JOIN seed AS r ON m.x = r.x ORDER BY r.y",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(_),
  )
}

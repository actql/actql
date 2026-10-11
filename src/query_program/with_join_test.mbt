///|
fn checked_with_join(
  text : String,
  context : Context,
) -> @program.Program raise {
  let program = compile_query_script(
    @query.parse_query_script(text, syntax_limits()).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("WITH JOIN must retain its declared producers")
  }
  program
}

///|
test "WITH SQL and Pipe JOIN reuse existing logical producer inputs" {
  // Independently authored existing Values/projection/cross_join Program.
  // There is no acquisition or Stage boundary between these WITH bindings.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_script_cte_0"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_3"},{"from":"aql_script_seed_3","derive":{"aql_query_expr_0":{"literal":2}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_script_cte_2"},{"from":"aql_script_cte_0","cross_join":{"with":"aql_script_cte_2","max_output_rows":1000,"select":{"a":"left.id","b":"right.id"}},"as":"aql_join_output_6"},{"from":"aql_join_output_6","select":["a","b"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    body in [
      "SELECT l.id AS a, r.id AS b FROM lefts AS l CROSS JOIN rights AS r", "FROM lefts AS l |> CROSS JOIN rights AS r |> SELECT l.id AS a, r.id AS b",
    ] {
    let program = checked_with_join(
      "WITH lefts AS (SELECT 1 AS id), rights AS (SELECT 2 AS id), paired AS (" +
      body +
      ") FROM paired |> SELECT a, b",
      { ..fixture_context(), inputs: [], },
    )
    assert_eq(semantic(program), semantic(expected))
    assert_eq(@program.stage_count(program), 1)
  }
}

///|
test "several WITH JOINs have disjoint bindings and share one capture" {
  for
    text in [
      "WITH lefts AS (FROM orders |> SELECT id), first AS (SELECT l.id FROM lefts AS l JOIN lefts AS r ON l.id = r.id), second AS (SELECT l.id FROM first AS l JOIN lefts AS r ON l.id = r.id) FROM second |> SELECT id",
      "WITH joined AS (WITH seed AS (FROM orders |> SELECT id) SELECT l.id FROM seed AS l JOIN seed AS r ON l.id = r.id) FROM joined |> SELECT id",
    ] {
    let program = checked_with_join(text, {
      ..fixture_context(),
      captured_stage: Some("capture"),
    })
    assert_eq(@program.stage_count(program), 2)
    assert_eq(@program.export_count(program), 1)
    let body = semantic(program)
    assert_eq(body.split("\"carrier\":\"relation\"").length(), 2)
    assert_eq(body.split("\"stage\":\"capture\"").length(), 2)
  }
}

///|
test "WITH JOIN shares alias ORDER resolution and hides sort slots" {
  for
    suffix in [
      "SELECT l.x AS y FROM seed AS l JOIN seed AS r ON l.x = r.x ORDER BY y + 1",
      "SELECT l.x + 1 AS a, l.x + 1 AS b FROM seed AS l JOIN seed AS r ON l.x = r.x ORDER BY l.x + 1",
      "SELECT l.x AS y FROM seed AS l JOIN seed AS r ON l.x = r.x ORDER BY l.y + 1",
    ] {
    let program = checked_with_join(
      "WITH seed AS (FROM t |> SELECT x, y), joined AS (" +
      suffix +
      ") FROM joined |> SELECT *",
      join_order_context(),
    )
    let body = semantic(program)
    assert_eq(@program.stage_count(program), 1)
    assert_true(body.contains("aql_join_sorted_"))
    if !suffix.contains("ORDER BY l.x + 1") {
      assert_true(body.contains("aql_join_visible_"))
    }
    assert_false(body.contains("\"fields\":[\"aql_join_sort_"))
    if suffix.contains("ORDER BY y + 1") {
      assert_false(body.contains("left.y"))
    }
  }
}

///|
test "WITH JOIN refuses invalid names and output limits without fallback" {
  for
    text in [
      "WITH seed AS (FROM orders |> SELECT id), joined AS (SELECT a.id FROM seed AS a JOIN seed AS a ON a.id = a.id) FROM joined |> SELECT id",
      "WITH seed AS (FROM orders |> SELECT id), joined AS (SELECT id FROM seed AS a JOIN seed AS b ON a.id = b.id) FROM joined |> SELECT id",
      "WITH seed AS (FROM orders |> SELECT id), joined AS (SELECT a.amount FROM seed AS a JOIN seed AS b ON a.id = b.id) FROM joined |> SELECT amount",
      "WITH seed AS (FROM orders |> SELECT id), joined AS (SELECT a.id FROM seed AS a JOIN missing AS b ON a.id = b.id) FROM joined |> SELECT id",
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
  let script = @query.parse_query_script(
    "WITH seed AS (FROM orders |> SELECT id) SELECT a.id FROM seed AS a JOIN seed AS b ON a.id = b.id",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile_query_script(script, fixture_context(), {
      ..construction_limits(),
      max_join_output_rows: 0L,
    })
    is Err(_),
  )
}

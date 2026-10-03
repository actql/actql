///|
test "Pipe AGGREGATE resolves input ranges before closing their scope" {
  let program = compile(
    @query.parse_query(
      "FROM pair AS before |> SET x = y |> AGGREGATE SUM(x) AS current_value, SUM(before.x) AS original_value GROUP BY before.x |> SELECT x, current_value, original_value",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(program)
  // Independent existing-IR expectation: SET changes current x to y=9, while
  // before.x remains 7. Grouping and each aggregate name the actual value slot.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","derive":{"aql_pipe_set_2":{"field":"y"}}},{"group":{"by":["x"],"aggregates":{"current_value":{"fn":"sum","field":"aql_pipe_set_2"},"original_value":{"fn":"sum","field":"x"}}}},{"select":["x","current_value","original_value"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","current_value","original_value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(wire, semantic(expected))
  assert_true(wire.contains("\"by\":[\"x\"]"))
  assert_true(
    wire.contains(
      "\"current_value\":{\"field\":\"aql_pipe_set_2\",\"fn\":\"sum\"}",
    ),
  )
  assert_true(
    wire.contains("\"original_value\":{\"field\":\"x\",\"fn\":\"sum\"}"),
  )
  // SUM still needs the ordinary installed numeric profile; Frontend scope
  // resolution cannot manufacture that evidence.
  assert_true(
    @check.check_parsed(program, check_environment(), None, check_limits())
    is NeedsInputs(_),
  )
  match
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("scoped aggregate Values must be closed")
  }
}

///|
test "Pipe AGGREGATE rejects old input ranges with and without private slots" {
  for prefix in ["", " |> SET x = y"] {
    let query = @query.parse_query(
      "FROM pair AS before" +
      prefix +
      " |> AGGREGATE COUNT(*) AS n GROUP BY before.x |> SELECT before.x, n",
      syntax_limits(),
    ).unwrap()
    assert_true(compile(query, pair_context(), construction_limits()) is Err(_))
  }
}

///|
test "SQL JOIN grouping retains only grouped qualified slots and aliases" {
  for
    query in [
      "SELECT l.x AS bucket, COUNT(*) AS n FROM t AS l JOIN t AS r ON l.x = r.x JOIN t AS s ON r.x = s.x GROUP BY bucket HAVING bucket > 0 ORDER BY n + 1",
      "SELECT l.x + 1 AS bucket, COUNT(*) AS n FROM t AS l JOIN t AS r ON l.x = r.x JOIN t AS s ON r.x = s.x GROUP BY bucket HAVING bucket > 0 ORDER BY bucket",
    ] {
    let program = compile(
      @query.parse_query(query, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    assert_true(semantic(program).contains("\"fields\":[\"bucket\",\"n\"]"))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("grouped JOIN Values must be closed")
    }
  }
  for
    query in [
      "SELECT r.y, COUNT(*) AS n FROM t AS l JOIN t AS r ON l.x = r.x JOIN t AS s ON r.x = s.x GROUP BY l.x",
      "SELECT l.x, COUNT(*) AS n FROM t AS l JOIN t AS r ON l.x = r.x JOIN t AS s ON r.x = s.x GROUP BY l.x HAVING r.y > 0",
    ] {
    assert_true(
      compile(
        @query.parse_query(query, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "Pipe JOIN aggregation projects keys after physical grouping" {
  let program = compile(
    @query.parse_query(
      "FROM t AS l |> JOIN t AS r ON l.x = r.x |> JOIN t AS s ON r.x = s.x |> AGGREGATE COUNT(*) AS n GROUP BY l.x |> SELECT x, n",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"by\":[\"aql_chain_column_2\"]"))
  assert_true(
    wire.contains("\"select\":[{\"x\":\"aql_chain_column_2\"},\"n\"]"),
  )
  assert_true(wire.contains("\"fields\":[\"x\",\"n\"]"))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("Pipe grouped JOIN Values must be closed")
  }
}

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
test "global SUM retains the original range after SET and DROP" {
  for operation in ["SET x = y", "DROP x"] {
    let program = compile(
      @query.parse_query(
        "FROM pair AS before |> " +
        operation +
        " |> AGGREGATE SUM(before.x) AS total",
        syntax_limits(),
      ).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    // The original x=7 is retained even though current x becomes 9 or is
    // dropped. SUM must consume x, not the new/current value or an empty row.
    assert_true(
      semantic(program).contains(
        "\"aggregates\":{\"total\":{\"field\":\"x\",\"fn\":\"sum\"}}",
      ),
    )
    assert_true(semantic(program).contains("\"fields\":[\"total\"]"))
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("global SUM uses the existing numeric profile")
    }
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

///|
test "authored public grouping sources pass ordinary script admission and checking" {
  // Same independently authored input rows as the public fixture. Here they
  // are Values, so this verifies lowering/checking, not acquisition or Host I/O.
  let values = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"amount":{"type":"number","nullable":true},"id":{"type":"number","nullable":false}},"rows":[{"id":3,"amount":30},{"id":1,"amount":null},{"id":2,"amount":20},{"id":3,"amount":30}]},"as":"records"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let context = {
    ..pair_context(),
    inputs: [
      {
        relation: [{ value: "records", quoted: false, }],
        name: "records",
        source: GeneratedValues(values),
        visible_fields: ["amount", "id"],
        graph_bindings: [],
      },
    ],
  }
  for
    (source, fields) in [
      (
        "SELECT 7 AS x, 9 AS y |> AS before |> SET x = y |> AGGREGATE COUNT(*) AS n GROUP BY before.x |> ORDER BY x",
        "\"fields\":[\"x\",\"n\"]",
      ),
      (
        "SELECT 7 AS x, 9 AS y |> AS before |> SET x = y |> AGGREGATE COUNT(*) AS n GROUP BY x |> ORDER BY x",
        "\"fields\":[\"x\",\"n\"]",
      ),
      (
        "WITH t AS (SELECT 2 AS x, 10 AS y UNION ALL SELECT 1 AS x, 20 AS y) SELECT l.x + 1 AS y, COUNT(*) AS n FROM t AS l JOIN t AS r ON l.x = r.x JOIN t AS s ON r.x = s.x GROUP BY y HAVING y > 1 ORDER BY y",
        "\"fields\":[\"y\",\"n\"]",
      ),
      (
        "WITH t AS (SELECT 2 AS x, 10 AS y UNION ALL SELECT 1 AS x, 20 AS y) FROM t AS l |> JOIN t AS r ON l.x = r.x |> JOIN t AS s ON r.x = s.x |> AGGREGATE COUNT(*) AS n GROUP BY l.x |> SELECT x, n |> ORDER BY x",
        "\"fields\":[\"x\",\"n\"]",
      ),
      (
        "SELECT CAST(NULL AS FLOAT64) AS x WHERE FALSE |> AS before |> AGGREGATE COUNT(*) AS n GROUP BY before.x |> ORDER BY x",
        "\"fields\":[\"x\",\"n\"]",
      ),
      (
        "DATA seed = FROM records |> SELECT id; SELECT l.id AS id, COUNT(*) AS n FROM seed AS l JOIN seed AS r ON l.id = r.id JOIN seed AS s ON r.id = s.id GROUP BY id ORDER BY id",
        "\"fields\":[\"id\",\"n\"]",
      ),
    ] {
    let program = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    assert_true(semantic(program).contains(fields), msg=source)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("authored grouping Values must be closed")
    }
  }
}

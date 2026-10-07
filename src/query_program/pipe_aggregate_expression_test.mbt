///|
test "Pipe aggregate scalar expressions match an independent checked Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","group":{"by":["x"],"aggregates":{"aql_select_aggregate_0":{"fn":"count"}}}},{"derive":{"aql_pipe_aggregate_0":{"add":[{"field":"aql_select_aggregate_0"},{"literal":1}]}}},{"select":[{"bucket":"x"},{"n":"aql_pipe_aggregate_0"}]},{"select":["bucket","n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["bucket","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ =>
      fail(
        "common group and derive admit the independently authored scalar aggregate",
      )
  }
  let actual = compile(
    @query.parse_query(
      "FROM pair |> AGGREGATE COUNT(*) + 1 AS n GROUP BY x AS bucket",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "Pipe aggregate scalar expressions retain input scope and reuse checked calls" {
  for
    (source, calls) in [
      ("FROM pair |> AGGREGATE COUNT(*) + COUNT(*) AS n", 1),
      (
        "FROM pair |> AGGREGATE COUNT(*) + (x + 1) AS n GROUP BY x + 1 AS bucket",
        1,
      ),
      (
        "FROM pair |> AGGREGATE COUNT(*) + (pair.x + 1) AS n GROUP BY x + 1 AS bucket",
        1,
      ),
      ("FROM pair |> AGGREGATE COUNT(*) AS n, COUNT(*) + 1 AS next", 1),
      ("FROM pair |> AGGREGATE SUM(x) + SUM(pair.x) AS total", 1),
      ("FROM pair |> AGGREGATE COUNT(*) + x AS x GROUP BY x AS bucket", 1),
      ("FROM pair |> AGGREGATE SUM(x) + y AS total GROUP BY y AS x", 1),
      ("FROM pair |> AGGREGATE SUM(x) AS x GROUP BY x AS bucket", 1),
      (
        "FROM pair |> AS before |> AGGREGATE SUM(before.x) + before.y AS total GROUP BY before.y AS x",
        1,
      ),
      ("FROM pair |> AGGREGATE COALESCE(SUM(y), 0) + 1 AS total", 1),
      (
        "FROM pair |> WHERE FALSE |> AGGREGATE COALESCE(SUM(y), 0) + 1 AS total",
        1,
      ),
      (
        "FROM pair |> AGGREGATE COUNT(*) + 1 AS n DESC GROUP AND ORDER BY x AS bucket |> WHERE n > 1 |> LIMIT 1",
        1,
      ),
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(
      semantic(program).split("\"fn\":").length() - 1,
      calls,
      msg=source,
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
      _ =>
        fail(
          "ordinary grouped scalar expressions have closed Values inputs: " +
          source,
        )
    }
  }
}

///|
test "Pipe aggregate scalar expressions reject ungrouped and sibling bindings" {
  for
    source in [
      "FROM pair |> AGGREGATE COUNT(*) + x AS n", "FROM pair |> AGGREGATE COUNT(*) + pair.x AS n",
      "FROM pair |> AGGREGATE COUNT(*) + 1 AS n, COUNT(*) + n AS next", "FROM pair |> AGGREGATE COUNT(*) AS n, COUNT(*) + n AS next",
      "FROM pair |> AGGREGATE COUNT(*) + bucket AS n GROUP BY x AS bucket", "FROM pair |> AS before |> AS after |> AGGREGATE COUNT(*) + before.x AS n GROUP BY after.x",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=source,
    )
  }
}

///|
test "Pipe aggregate scalar expressions bind a computed key in an independent complete Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","derive":{"aql_group_key_0":{"add":[{"field":"x"},{"literal":1}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"aql_select_aggregate_0":{"fn":"count"}}}},{"derive":{"aql_pipe_aggregate_0":{"add":[{"field":"aql_select_aggregate_0"},{"field":"aql_group_key_0"}]}}},{"select":[{"bucket":"aql_group_key_0"},{"n":"aql_pipe_aggregate_0"}]},{"select":["bucket","n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["bucket","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent computed key uses a single evaluated input slot")
  }
  let actual = compile(
    @query.parse_query(
      "FROM pair |> AGGREGATE COUNT(*) + (pair.x + 1) AS n GROUP BY x + 1 AS bucket",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

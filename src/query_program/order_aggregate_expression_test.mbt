///|
test "ORDER aggregate expression matches an independent complete Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":["x"],"aggregates":{"aql_order_aggregate_0":{"fn":"count"}}}},{"derive":{"aql_pipe_sort_3":{"add":[{"field":"aql_order_aggregate_0"},{"literal":1}]}}},{"sort":[{"field":"aql_pipe_sort_3","dir":"asc","nulls":"first"},{"field":"x","dir":"asc","nulls":"first"}]},{"select":["x"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(
      expected,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent Group/sort control has closed Values inputs")
  }
  let generated = compile(
    @query.parse_query(
      "SELECT x FROM t GROUP BY x ORDER BY COUNT(*) + 1, x",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(generated), semantic(expected))
}

///|
test "ORDER aggregate expression reuses only matching argument meanings" {
  for
    (source, calls) in [
      ("SELECT x FROM t GROUP BY x ORDER BY COUNT(*) + COUNT(*), x", 1),
      ("SELECT x, COUNT(*) AS n FROM t GROUP BY x ORDER BY COUNT(*) + 1, x", 1),
      (
        "SELECT -x AS x, SUM(t.x) AS total FROM t GROUP BY t.x ORDER BY SUM(x), x",
        2,
      ),
      (
        "SELECT -x AS x, SUM(t.x) AS total FROM t GROUP BY t.x ORDER BY SUM(t.x), x",
        1,
      ),
      (
        "SELECT x FROM t GROUP BY x HAVING SUM(y) > 0 ORDER BY SUM(t.y) NULLS LAST, x",
        1,
      ),
      ("SELECT 1 AS marker FROM t ORDER BY COUNT(*) + 1", 1),
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
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
          "grouped ORDER uses the existing closed numeric profile: " + source,
        )
    }
  }
}

///|
test "ORDER aggregate expression after DISTINCT must use selected values" {
  for
    source in [
      "SELECT DISTINCT COUNT(*) + 1 AS n FROM t GROUP BY x ORDER BY COUNT(*) + 1",
      "SELECT DISTINCT COUNT(*) AS n FROM t GROUP BY x ORDER BY COUNT(*) + 1",
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("selected aggregate values are available after DISTINCT")
    }
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT DISTINCT x FROM t GROUP BY x ORDER BY COUNT(*)",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnsupportedOrdering),
  )
}

///|
test "ORDER aggregate expression preserves nested and ungrouped refusals" {
  for
    source in [
      "SELECT x FROM t ORDER BY COUNT(*)", "SELECT x, COUNT(*) AS n FROM t GROUP BY x ORDER BY SUM(n)",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=source,
    )
  }
}

///|
test "ORDER aggregate expression retains CTE and completed Pipe scopes" {
  for
    source in [
      "WITH summary AS (SELECT x FROM t GROUP BY x ORDER BY COUNT(*) + 1, x LIMIT 1) SELECT x FROM summary",
      "SELECT x FROM t GROUP BY x ORDER BY COUNT(*) + 1, x |> SELECT x + 1 AS next |> ORDER BY next",
    ] {
    let program = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("completed grouped ORDER feeds existing CTE/Pipe consumers")
    }
  }
}

///|
test "ORDER aggregate expression does not mutate shared HAVING syntax" {
  let query = @query.parse_query(
    "SELECT x FROM t GROUP BY x HAVING COUNT(*) > 0 ORDER BY COUNT(*) + 1, x",
    syntax_limits(),
  ).unwrap()
  let first = compile(query, join_order_context(), construction_limits()).unwrap()
  let repeated = compile(query, join_order_context(), construction_limits()).unwrap()
  assert_eq(semantic(first), semantic(repeated))
  guard @query.operation_at(query, 1) is Some(Having(_, calls)) else {
    fail("expected authored HAVING")
  }
  assert_eq(calls.length(), 1)
}

///|
test "ORDER aggregate expression keeps implicit star inputs distinct from private calls" {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"aql_order_aggregate_0":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"aql_order_aggregate_0":1,"y":20},{"aql_order_aggregate_0":2,"y":10}]},"as":"t"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let context = {
    ..join_order_context(),
    inputs: [
      {
        relation: [{ value: "t", quoted: false, }],
        name: "t",
        source: GeneratedValues(seed),
        visible_fields: ["aql_order_aggregate_0", "y"],
        graph_bindings: [],
      },
    ],
  }
  let program = compile(
    @query.parse_query(
      "SELECT * FROM t GROUP BY 1, 2 ORDER BY COUNT(*) + 1, y",
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_order_aggregate_0":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"aql_order_aggregate_0":1,"y":20},{"aql_order_aggregate_0":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":["aql_order_aggregate_0","y"],"aggregates":{"aql_having_aggregate_2":{"fn":"count"}}}},{"derive":{"aql_pipe_sort_5":{"add":[{"field":"aql_having_aggregate_2"},{"literal":1}]}}},{"sort":[{"field":"aql_pipe_sort_5","dir":"asc","nulls":"first"},{"field":"y","dir":"asc","nulls":"first"}]},{"select":["aql_order_aggregate_0","y"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["aql_order_aggregate_0","y"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(
      expected,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the authored star/call collision keeps both physical values")
  }
  assert_eq(semantic(program), semantic(expected))
}

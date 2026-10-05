///|
test "SELECT aggregate expression matches an independent complete Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":[],"aggregates":{"aql_select_aggregate_0":{"fn":"count"}}}},{"derive":{"aql_query_expr_0":{"add":[{"field":"aql_select_aggregate_0"},{"literal":1}]}}},{"select":[{"next":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["next"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
    _ => fail("the independent grouped expression has closed Values inputs")
  }
  let generated = compile(
    @query.parse_query("SELECT COUNT(*) + 1 AS next FROM t", syntax_limits()).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(generated), semantic(expected))
}

///|
test "SELECT aggregate expression reuses only identical input meanings" {
  for
    (source, calls) in [
      ("SELECT COUNT(*) + COUNT(*) AS n FROM t", 1),
      ("SELECT COUNT(*) AS n, COUNT(*) + 1 AS next FROM t", 1),
      ("SELECT SUM(y) + SUM(t.y) AS total FROM t", 1),
      (
        "SELECT -x AS x, SUM(t.x) + COUNT(*) AS total FROM t GROUP BY t.x ORDER BY x",
        2,
      ),
      ("SELECT COALESCE(SUM(y), 0) + 1 AS total FROM t", 1),
      (
        "SELECT x, COUNT(*) + 1 AS n FROM t GROUP BY x HAVING n > 1 ORDER BY n DESC, x",
        1,
      ),
      ("SELECT x, COUNT(*) AS n FROM t GROUP BY x HAVING COUNT(*) > 0", 1),
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
          "the existing numeric profile closes selected aggregates: " + source,
        )
    }
  }
}

///|
test "SELECT aggregate expression keeps sibling and ungrouped input refusals" {
  for
    source in [
      "SELECT COUNT(*) + 1 AS n, n + 1 AS next FROM t", "SELECT n + 1 AS next, COUNT(*) + 1 AS n FROM t",
      "SELECT SUM(y) + x AS n FROM t", "SELECT SUM(y) + t.x AS n FROM t", "SELECT COUNT(*) + 1 AS x, x + 1 AS next FROM t",
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
test "SELECT aggregate expression retains CTE and completed Pipe scopes" {
  for
    source in [
      "WITH summary AS (SELECT COUNT(*) + 1 AS n FROM t) SELECT n FROM summary ORDER BY n",
      "SELECT COUNT(*) + 1 AS n FROM t |> SELECT n + 1 AS next |> ORDER BY next",
      "SELECT COUNT(*) + 1 AS n FROM t |> WHERE n > 1 |> SELECT n", "SELECT COUNT(*) + 1 AS n FROM t |> AS summary |> SELECT summary.n",
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
      _ =>
        fail(
          "ordinary grouped expressions feed existing CTE/Pipe consumers: " +
          source,
        )
    }
  }
}

///|
test "SELECT aggregate expression keeps implicit star columns with private-looking names" {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"aql_select_aggregate_0":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"aql_select_aggregate_0":1,"y":20},{"aql_select_aggregate_0":2,"y":10}]},"as":"t"}
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
        visible_fields: ["aql_select_aggregate_0", "y"],
        graph_bindings: [],
      },
    ],
  }
  let program = compile(
    @query.parse_query(
      "SELECT *, COUNT(*) + 1 AS next FROM t GROUP BY 1, 2 ORDER BY next, y",
      syntax_limits(),
    ).unwrap(),
    context,
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
    _ => fail("private-looking input keys remain ordinary star columns")
  }
  // The existing allocator starts at the four supplied physical entries:
  // two input columns plus the two retained group keys. This spelling is
  // allocation bookkeeping; the original input and aggregate are distinct.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_select_aggregate_0":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"aql_select_aggregate_0":1,"y":20},{"aql_select_aggregate_0":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":["aql_select_aggregate_0","y"],"aggregates":{"aql_select_aggregate_4":{"fn":"count"}}}},{"derive":{"aql_query_expr_2":{"add":[{"field":"aql_select_aggregate_4"},{"literal":1}]}}},{"select":["aql_select_aggregate_0","y",{"next":"aql_query_expr_2"}]},{"sort":[{"field":"next","dir":"asc","nulls":"first"},{"field":"y","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["aql_select_aggregate_0","y","next"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
}

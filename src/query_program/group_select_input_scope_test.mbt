///|
test "GROUP SELECT siblings cannot read a newly declared aggregate alias" {
  for
    source in [
      "SELECT COUNT(*) AS n, n + 1 AS next FROM t", "SELECT n + 1 AS next, COUNT(*) AS n FROM t",
      "SELECT COUNT(*) AS n, t.n AS next FROM t", "SELECT COUNT(*) AS n, `N` + 1 AS next FROM t",
      "SELECT COUNT(*) AS n FROM t |> SELECT t.x AS next",
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
test "GROUP SELECT retains qualified grouped JOIN inputs without aggregate alias leakage" {
  let source = "WITH a AS (SELECT 1 AS x), b AS (SELECT 1 AS k), c AS (SELECT 1 AS z) SELECT a.x AS x, COUNT(*) AS n FROM a JOIN b ON a.x = b.k JOIN c ON b.k = c.z GROUP BY a.x HAVING n > 0 ORDER BY n + x"
  let program = compile_query_script(
    @query.parse_query_script(source, syntax_limits()).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("grouped JOIN input and aggregate output must be closed")
  }
}

///|
test "GROUP SELECT does not substitute an aggregate for an ungrouped input" {
  for
    source in [
      "SELECT COUNT(*) AS x, x + 1 AS next FROM t", "SELECT COUNT(*) AS x, t.x AS next FROM t GROUP BY y",
      "WITH a AS (SELECT 1 AS x), b AS (SELECT 1 AS k), c AS (SELECT 1 AS z) SELECT COUNT(*) AS n, n + 1 AS next FROM a JOIN b ON a.x = b.k JOIN c ON b.k = c.z",
    ] {
    assert_true(
      compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=source,
    )
  }
}

///|
test "GROUP SELECT preserves ordinary constants and visible aggregate outputs" {
  let program = compile(
    @query.parse_query("SELECT COUNT(*) AS n, 1 AS one FROM t", syntax_limits()).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":[],"aggregates":{"n":{"fn":"count"}}}},{"derive":{"aql_query_expr_1":{"literal":1}}},{"select":["n",{"one":"aql_query_expr_1"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["n","one"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("global COUNT and constant Values must be closed")
  }
}

///|
test "GROUP SELECT keeps grouped input expressions and HAVING ORDER aliases" {
  for
    source in [
      "SELECT x + 1 AS next, COUNT(*) AS n FROM t GROUP BY x HAVING n > 0 ORDER BY next",
      "SELECT t.x AS x, COUNT(*) AS n FROM t GROUP BY x HAVING n > 0 ORDER BY n + x",
      "SELECT -x AS x, COUNT(*) AS n FROM t GROUP BY x ORDER BY x", "SELECT COUNT(*) AS n FROM t |> SELECT n, n + 1 AS next |> ORDER BY next",
      "FROM t |> AGGREGATE COUNT(*) AS n |> SELECT n, n + 1 AS next |> ORDER BY next",
      "SELECT COUNT(*) AS n FROM t |> WHERE n > 0 |> SELECT n", "SELECT COUNT(*) AS n FROM t |> SET n = n + 1 |> SELECT n",
      "SELECT COUNT(*) AS n FROM t |> AS summary |> SELECT summary.n",
    ] {
    let result = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    assert_true(result is Ok(_), msg=source)
    match
      @check.check_parsed(
        result.unwrap(),
        check_environment(),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("retained GROUP and next Pipe values must be closed")
    }
  }
}

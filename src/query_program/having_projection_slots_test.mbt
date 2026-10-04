///|
test "HAVING projection aliases retain computed grouped input values" {
  for
    source in [
      "SELECT x + 1 AS y, COUNT(*) AS n FROM t GROUP BY x HAVING y > 2 ORDER BY y",
      "SELECT -x AS x, COUNT(*) AS n FROM t GROUP BY t.x HAVING x < 0 AND t.x > 0 ORDER BY x",
      "SELECT x + 1 AS next, x + 1 AS also, COUNT(*) AS n FROM t GROUP BY x HAVING next > 2 AND also < 4 ORDER BY next",
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("computed HAVING aliases must use closed grouped input values")
    }
  }
}

///|
test "HAVING projection aliases retain qualified grouped JOIN input values" {
  let source = "WITH a AS (SELECT 1 AS x), b AS (SELECT 1 AS k), c AS (SELECT 1 AS z) SELECT a.x + 1 AS next, COUNT(*) AS n FROM a JOIN b ON a.x = b.k JOIN c ON b.k = c.z GROUP BY a.x HAVING next > 1 ORDER BY next"
  let program = compile_query_script(
    @query.parse_query_script(source, syntax_limits()).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("scoped HAVING must use the grouped JOIN input slot")
  }
}

///|
test "HAVING projection aliases share one evaluated physical slot" {
  let source = "SELECT x + 1 AS next, x + 1 AS also, COUNT(*) AS n FROM t GROUP BY x HAVING next > 2 AND also < 4 ORDER BY next"
  let program = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  // This complete expected Program is written independently. Both HAVING
  // references and both SELECT outputs use the single grouped derivation.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":["x"],"aggregates":{"n":{"fn":"count"}}}},{"derive":{"aql_having_expr_5":{"add":[{"field":"x"},{"literal":1}]}}},{"filter":{"and":[{"gt":[{"field":"aql_having_expr_5"},{"literal":2}]},{"lt":[{"field":"aql_having_expr_5"},{"literal":4}]}]}},{"select":[{"next":"aql_having_expr_5"},{"also":"aql_having_expr_5"},"n"]},{"sort":[{"field":"next","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["next","also","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent shared HAVING slot Program must be closed")
  }
}

///|
test "HAVING projection aliases do not restore ungrouped or sibling references" {
  for
    source in [
      "SELECT y + 1 AS next, COUNT(*) AS n FROM t GROUP BY x HAVING next > 0", "SELECT x + 1 AS next, next + 1 AS sibling, COUNT(*) AS n FROM t GROUP BY x HAVING next > 0",
      "SELECT x + 1 AS next, COUNT(*) AS n FROM t GROUP BY x HAVING t.next > 0",
      "SELECT x + 1 AS next, x + 2 AS next, COUNT(*) AS n FROM t GROUP BY x HAVING next > 0",
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
test "HAVING projection aliases retain expression limits and original origin" {
  let source = "SELECT y + 1 AS next, COUNT(*) AS n FROM t GROUP BY x HAVING next > 0"
  guard compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(
      Expression({ issue: @expression.UnknownReference, origin: Some(origin), })
    ) else {
    fail("ungrouped alias input must retain its typed source diagnostic")
  }
  assert_eq(@origin.start(origin).utf16_offset, 7)
  assert_eq(@origin.end(origin).utf16_offset, 8)
  let limits = { ..construction_limits(), max_expression_work: 2, }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT x + 1 AS next, COUNT(*) AS n FROM t GROUP BY x HAVING next > 0",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      limits,
    )
    is Err(Expression({ issue: @expression.WorkLimit, .. })),
  )
}

///|
test "HAVING projection aliases expire before the next Pipe projection" {
  let source = "SELECT x + 1 AS x, COUNT(*) AS n FROM t GROUP BY t.x HAVING x > 0 |> SELECT x + 1 AS next, n |> ORDER BY next"
  let program = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("next Pipe expression must consume the projected value")
  }
}

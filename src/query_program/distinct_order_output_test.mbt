///|
test "SQL DISTINCT ORDER computes an expression from the projected alias" {
  let program = compile(
    @query.parse_query(
      "SELECT DISTINCT -x AS x FROM t ORDER BY -x",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  // DISTINCT compares only x. ORDER consumes that evaluated output, not
  // the input x, and its helper is removed before the Named Result.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","derive":{"aql_query_expr_0":{"negate":{"field":"x"}}}},{"select":[{"x":"aql_query_expr_0"}]},{"distinct":["x"]},{"derive":{"aql_pipe_sort_2":{"negate":{"field":"x"}}}},{"sort":[{"field":"aql_pipe_sort_2","dir":"asc","nulls":"first"}]},{"select":["x"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("DISTINCT and ORDER use ordinary checked Relation operations")
  }
}

///|
test "SQL DISTINCT ORDER shares its helper and does not reevaluate SELECT" {
  let body = checked_join_order(
    "SELECT DISTINCT x + 1 AS score FROM t ORDER BY -score, -score DESC LIMIT 1",
  )
  assert_eq(body.split("\"add\":").length(), 2)
  assert_eq(body.split("\"negate\":").length(), 2)
  assert_true(body.contains("\"distinct\":[\"score\"]"))
  assert_true(body.contains("\"take\":{\"count\":1,\"offset\":0}"))
  assert_true(body.contains("\"fields\":[\"score\"]"))
}

///|
test "SQL DISTINCT ORDER reuses the selected expression without a helper" {
  let body = checked_join_order(
    "SELECT DISTINCT x + 1 AS score FROM t ORDER BY x + 1",
  )
  assert_eq(body.split("\"add\":").length(), 2)
  assert_false(body.contains("aql_pipe_sort_"))
}

///|
test "SQL DISTINCT ORDER cannot read an unselected input expression" {
  for
    source in [
      "SELECT DISTINCT x AS score FROM t ORDER BY y + 1", "SELECT DISTINCT x AS score FROM t ORDER BY t.y + 1",
      "SELECT DISTINCT -x AS x FROM t ORDER BY t.x", "FROM t |> AS original |> SELECT DISTINCT -x AS x |> ORDER BY original.x",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(_),
    )
  }
}

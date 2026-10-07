///|
test "GROUP reuses equivalent admitted FLOAT64 literal spellings" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","derive":{"aql_group_key_0":{"add":[{"field":"x"},{"literal":1}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"next":"aql_group_key_0"},"n"]},{"sort":[{"field":"next","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["next","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for (selected, grouped) in [("1.0", "1e0"), ("1e0", "1.00"), (".1e1", "1.")] {
    let text = "SELECT x + " +
      selected +
      " AS next, COUNT(*) AS n FROM t GROUP BY x + " +
      grouped +
      " ORDER BY next"
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(expected), msg=text)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("equivalent admitted literals must reuse the grouped value")
    }
  }
}

///|
test "GROUP does not equate different or inadmissible numeric literals" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT x + 2.0 AS next, COUNT(*) AS n FROM t GROUP BY x + 1e0",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT x + 9007199254740992.0 AS next, COUNT(*) AS n FROM t GROUP BY x + 9007199254740992",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.InvalidNumber, .. })),
  )
}

///|
test "DISTINCT ORDER reuses equivalent admitted literals without reviving inputs" {
  let program = compile(
    @query.parse_query(
      "SELECT DISTINCT x + 1.0 AS next FROM t ORDER BY t.x + 1e0",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","derive":{"aql_query_expr_0":{"add":[{"field":"x"},{"literal":1}]}}},{"select":[{"next":"aql_query_expr_0"}]},{"distinct":["next"]},{"sort":[{"field":"next","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["next"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("ORDER must consume the already selected value")
  }
}

///|
test "repeated SQL computed GROUP keys reuse the same independently checked value" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","derive":{"aql_group_key_0":{"add":[{"field":"x"},{"literal":1}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"aql_select_aggregate_0":{"fn":"count"}}}},{"derive":{"aql_query_expr_0":{"add":[{"field":"aql_select_aggregate_0"},{"field":"aql_group_key_0"}]}}},{"select":[{"n":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent repeated-key control has no acquisition")
  }
  for keys in ["x + 1, x + 1", "x + 1, (pair.x + 1)", "(pair.x + 1), x + 1"] {
    let actual = compile(
      @query.parse_query(
        "SELECT COUNT(*) + (pair.x + 1) AS n FROM pair GROUP BY " + keys,
        syntax_limits(),
      ).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("repeated-key source has no acquisition")
    }
    assert_eq(semantic(actual), semantic(expected), msg=keys)
  }
}

///|
test "repeated SQL direct and star ordinal keys keep an independent single key list" {
  for
    (source, by, selected) in [
      (
        "SELECT x, COUNT(*) AS n FROM t GROUP BY x, t.x, 1", "[\"x\"]", "[\"x\",\"n\"]",
      ),
      (
        "SELECT *, COUNT(*) AS n FROM t GROUP BY 1, 2, x, y, 1", "[\"x\",\"y\"]",
        "[\"x\",\"y\",\"n\"]",
      ),
    ] {
    let expected = @program.parse(
      (
        #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":
      ) +
      by +
      (
        #|,"aggregates":{"n":{"fn":"count"}}}},{"select":
      ) +
      selected +
      (
        #|,"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":
      ) +
      selected +
      (
        #|}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
      ),
      construction_limits().program,
      format=Json,
    ).unwrap()
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    for program in [expected, actual] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        Rejected(error) => raise @check.diagnostic_cause(error)
        _ => fail("independent repeated-key control has no acquisition")
      }
    }
    assert_eq(semantic(actual), semantic(expected), msg=source)
  }
}

///|
test "SQL GROUP reuse preserves different resolved receivers and Pipe output aliases" {
  let distinct = checked_group_property(
    "SELECT payload.score AS current, other.score AS original, COUNT(*) AS n FROM objects GROUP BY payload.score, other.score, (objects.payload).score",
  )
  assert_eq(semantic(distinct).split("\"property\":").length(), 3)
  let joined = compile_query_script(
    @query.parse_query_script(
      "SELECT l.x + 1 AS first, r.x + 1 AS second, COUNT(*) AS n FROM t AS l JOIN t AS r ON l.x = r.x GROUP BY l.x + 1, r.x + 1, (l.x + 1)",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(joined, check_environment(), None, check_limits())
    is Checked(_),
  )
  assert_eq(semantic(joined).split("\"aql_group_key_2\":").length(), 1)
  assert_true(
    semantic(joined).contains(
      "\"by\":[\"aql_group_key_0\",\"aql_group_key_1\"]",
    ),
  )
  let pipe = compile(
    @query.parse_query(
      "FROM t |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 AS first, x + 1 AS second",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(pipe, check_environment(), None, check_limits())
    is Checked(_),
  )
  assert_true(
    semantic(pipe).contains("\"fields\":[\"first\",\"second\",\"n\"]"),
  )
}

///|
test "SQL repeated key comparison preserves the bounded expression work refusal" {
  let query = @query.parse_query(
    "SELECT COUNT(*) AS n FROM t GROUP BY x, t.x, (x)",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, join_order_context(), {
      ..construction_limits(),
      max_expression_work: 5,
    })
    is Err(Expression({ issue: @expression.WorkLimit, origin: Some(_), })),
  )
}

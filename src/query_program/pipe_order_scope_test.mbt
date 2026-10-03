///|
test "Pipe ORDER evaluates a rebound alias against its selected value" {
  let program = compile(
    @query.parse_query(
      "FROM pair |> AS original |> SELECT -x AS x |> ORDER BY -x",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  // Authored from the scope contract: SELECT negates input x; ORDER negates
  // that evaluated result. They are different expressions despite the spelling.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","derive":{"aql_pipe_expr_2":{"negate":{"field":"x"}}}},{"derive":{"aql_pipe_sort_3":{"negate":{"field":"aql_pipe_expr_2"}}}},{"sort":[{"field":"aql_pipe_sort_3","dir":"asc","nulls":"first"}]},{"select":[{"x":"aql_pipe_expr_2"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("Values and the evaluated ORDER expression are closed")
  }
}

///|
test "Pipe ORDER collision checks survive DISTINCT materialization" {
  let wire = checked_join_order(
    "FROM t |> AS original |> SELECT DISTINCT -x AS x |> ORDER BY -x",
  )
  assert_eq(wire.split("\"negate\":").length(), 3)
  assert_true(wire.contains("\"distinct\":[\"x\"]"))
  assert_true(wire.contains("\"negate\":{\"field\":\"x\"}"))
  assert_true(wire.contains("\"fields\":[\"x\"]"))
}

///|
test "Pipe ORDER reuses an unchanged selected expression once" {
  for distinct in ["", "DISTINCT "] {
    let wire = checked_join_order(
      "FROM t |> AS original |> SELECT " +
      distinct +
      "-x AS score |> ORDER BY -x",
    )
    assert_eq(wire.split("\"negate\":").length(), 2)
    assert_false(wire.contains("aql_pipe_sort_"))
    assert_true(wire.contains("\"fields\":[\"score\"]"))
  }
}

///|
test "Pipe ORDER qualified input keeps its preprojection meaning" {
  let wire = checked_join_order(
    "FROM t |> AS original |> SELECT -original.x AS x |> ORDER BY -original.x",
  )
  assert_eq(wire.split("\"negate\":").length(), 2)
  assert_false(wire.contains("aql_pipe_sort_"))
}

///|
test "Pipe ORDER shares hidden expressions without reevaluating SELECT" {
  let wire = checked_join_order(
    "FROM t |> AS original |> SELECT -x AS x |> ORDER BY -x, -x DESC",
  )
  assert_eq(wire.split("\"negate\":").length(), 3)
  assert_true(wire.contains("\"fields\":[\"x\"]"))
}

///|
test "Pipe ORDER cannot recover a displaced input range" {
  assert_true(
    compile(
      @query.parse_query(
        "FROM t AS before |> AS original |> SELECT -x AS x |> ORDER BY -before.x",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(_),
  )
}

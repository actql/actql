///|
fn expect_distinct_filter_calls(source : String) -> Unit raise {
  let generated = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(generated).split("\"fn\":").length() - 1, 2, msg=source)
}

///|
test "filtered SELECT calls match an independent complete Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":[],"aggregates":{"n_false":{"fn":"count","filter":{"literal":false}},"aql_select_aggregate_0":{"fn":"count","filter":{"literal":true}}}}},{"derive":{"aql_query_expr_1":{"add":[{"field":"aql_select_aggregate_0"},{"literal":0}]}}},{"select":["n_false",{"n_true":"aql_query_expr_1"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["n_false","n_true"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
    _ => fail("independently authored filtered count control is closed")
  }
  let generated = compile(
    @query.parse_query(
      "SELECT COUNT(* WHERE FALSE) AS n_false, COUNT(* WHERE TRUE) + 0 AS n_true FROM t",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(generated), semantic(expected))
}

///|
test "SELECT aggregate reuse distinguishes different filter predicates" {
  expect_distinct_filter_calls(
    "SELECT COUNT(* WHERE FALSE) AS n_false, COUNT(* WHERE TRUE) + 0 AS n_true FROM t",
  )
}

///|
test "SELECT aggregate reuse distinguishes absent and present filter" {
  expect_distinct_filter_calls(
    "SELECT COUNT(*) AS all_rows, COUNT(* WHERE FALSE) + 0 AS n_false FROM t",
  )
}

///|
test "HAVING aggregate reuse distinguishes different filter predicates" {
  expect_distinct_filter_calls(
    "SELECT COUNT(* WHERE FALSE) AS n_false FROM t HAVING COUNT(* WHERE TRUE) > 0",
  )
}

///|
test "ORDER aggregate reuse distinguishes different filter predicates" {
  expect_distinct_filter_calls(
    "SELECT x, COUNT(* WHERE FALSE) AS n_false FROM t GROUP BY x ORDER BY COUNT(* WHERE TRUE), x",
  )
}

///|
test "equal aggregate filters retain common result reuse" {
  let generated = compile(
    @query.parse_query(
      "SELECT COUNT(* WHERE TRUE) AS n, COUNT(* WHERE TRUE) + 0 AS same FROM t",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(generated).split("\"fn\":").length() - 1, 1)
}

///|
test "HAVING filter can resolve a pre-group selected alias" {
  let generated = compile(
    @query.parse_query(
      "SELECT x AS k FROM t GROUP BY x HAVING COUNT(* WHERE k > 1) > 0",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(
      generated,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("closed independent Values input")
  }
}

///|
test "ORDER aggregate filter can resolve a pre-group selected alias" {
  let generated = compile(
    @query.parse_query(
      "SELECT x AS k FROM t GROUP BY x ORDER BY COUNT(* WHERE k > 1), k",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(
      generated,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("closed independent Values input")
  }
}

///|
test "filter reuse respects equivalent qualified references" {
  let generated = compile(
    @query.parse_query(
      "SELECT COUNT(* WHERE x > 1) AS n, COUNT(* WHERE t.x > 1) + 0 AS same FROM t",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(generated).split("\"fn\":").length() - 1, 1)
}

///|
test "hidden filters distinguish aliases from qualified inputs" {
  for
    source in [
      "SELECT -x AS x FROM t GROUP BY t.x HAVING COUNT(* WHERE x < 0) > 0", "SELECT -x AS x FROM t GROUP BY t.x ORDER BY COUNT(* WHERE x < 0), x",
      "SELECT -x AS x FROM t GROUP BY t.x HAVING COUNT(* WHERE t.x > 0) > 0",
    ] {
    let generated = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        generated,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("closed independent Values input")
    }
  }
}

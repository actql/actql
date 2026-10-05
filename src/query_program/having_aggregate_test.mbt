///|
test "HAVING hidden aggregate matches the independent checked full Program" {
  // Group cardinality is computed before filtering, never from selected rows.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":["x"],"aggregates":{"aql_having_aggregate_0":{"fn":"count"}}}},{"filter":{"gt":[{"field":"aql_having_aggregate_0"},{"literal":1}]}},{"select":["x"]},{"sort":[{"field":"x","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent Values control requires no external inputs")
  }
  let generated = compile(
    @query.parse_query(
      "SELECT x FROM t GROUP BY x HAVING COUNT(*) > 1 ORDER BY x",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(generated), semantic(expected))
}

///|
test "HAVING hidden aggregates reuse only semantically identical input slots" {
  for
    (source, aggregate_count) in [
      (
        "SELECT x, SUM(y) AS total FROM t GROUP BY x HAVING SUM(t.y) > 10 AND SUM(y) < 30 ORDER BY x",
        1,
      ),
      (
        "SELECT -x AS x, SUM(t.x) AS total FROM t GROUP BY t.x HAVING SUM(x) < -1 ORDER BY x",
        2,
      ),
      (
        "SELECT x FROM t GROUP BY x HAVING COUNT(*) > 0 AND COUNT(*) < 3 ORDER BY x",
        1,
      ),
      ("SELECT COUNT(*) AS n FROM t HAVING COUNT(*) > 0", 1),
      ("SELECT 1 AS n FROM t HAVING COUNT(*) > 0", 1),
    ] {
    let generated = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    let text = semantic(generated)
    assert_eq(text.split("\"fn\":").length() - 1, aggregate_count, msg=source)
    match
      @check.check_parsed(
        generated,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("hidden aggregates have closed Values inputs: " + source)
    }
  }
}

///|
test "HAVING hidden aggregate rejects ungrouped and nested alias inputs" {
  for
    source in [
      "SELECT x FROM t GROUP BY x HAVING COUNT(*) > 0 AND y > 0", "SELECT x, COUNT(*) AS n FROM t GROUP BY x HAVING SUM(n) > 0",
      "SELECT x AS same, y AS same FROM t GROUP BY x, y HAVING SUM(same) > 0",
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
test "HAVING hidden aggregate shares the selected qualified aggregate Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":["x"],"aggregates":{"total":{"fn":"sum","field":"y"}}}},{"filter":{"and":[{"gt":[{"field":"total"},{"literal":10}]},{"lt":[{"field":"total"},{"literal":30}]}]}},{"select":["x","total"]},{"sort":[{"field":"x","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","total"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let source = "SELECT x, SUM(y) AS total FROM t GROUP BY x HAVING SUM(t.y) > 10 AND SUM(y) < 30 ORDER BY x"
  let generated = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(generated), semantic(expected))
  match
    @check.check_parsed(
      expected,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ =>
      fail(
        "the existing numeric profile closes the independent aggregate Program",
      )
  }
  guard @check.check_parsed(
      generated,
      check_environment(),
      None,
      check_limits(),
    )
    is NeedsInputs(requests) else {
    fail("SUM still requires its numeric profile")
  }
  assert_true(
    @check.input_request_at(requests, 0).unwrap().kind
    is NumericReductionProfile(_),
  )
}

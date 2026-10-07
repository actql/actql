///|
fn assert_star_order_program(
  expected_text : String,
  sources : Array[String],
) -> Unit raise {
  let expected = @program.parse(
    expected_text,
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
    _ => fail("independent original-input aggregate Program is closed")
  }
  for source in sources {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=source)
  }
}

///|
test "star REPLACE aggregate ORDER alias retains its same-name SELECT input" {
  // Authored from the original Values inputs, independently of compiler output.
  assert_star_order_program(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":["y"],"aggregates":{"x":{"fn":"sum","field":"x"}}}},{"select":["x","y"]},{"sort":[{"field":"x","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","y"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    [
      "SELECT * REPLACE (SUM(x) AS x) FROM t GROUP BY y ORDER BY x", "SELECT * REPLACE (SUM(x) AS x) FROM t GROUP BY y ORDER BY `x`",
      "SELECT SUM(x) AS x, y FROM t GROUP BY y ORDER BY `x`", "SELECT SUM(x) AS `x`, y FROM t GROUP BY y ORDER BY `x`",
    ],
  )
}

///|
test "star REPLACE aggregate ORDER alias retains simultaneous SELECT inputs" {
  // Authored from the original Values inputs, independently of compiler output.
  assert_star_order_program(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","derive":{"aql_group_key_0":{"add":[{"field":"y"},{"literal":1}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"x":{"fn":"sum","field":"y"}}}},{"select":["x",{"y":"aql_group_key_0"}]},{"sort":[{"field":"x","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","y"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    [
      "SELECT * REPLACE (SUM(y) AS x, y + 1 AS y) FROM t GROUP BY y ORDER BY x",
      "SELECT * REPLACE (SUM(y) AS x, y + 1 AS y) FROM t GROUP BY y ORDER BY `x`",
      "SELECT SUM(y) AS x, y + 1 AS y FROM t GROUP BY y ORDER BY `x`", "SELECT SUM(y) AS `x`, y + 1 AS y FROM t GROUP BY y ORDER BY `x`",
    ],
  )
}

///|
test "star REPLACE retains genuine ORDER-only aggregate alias inputs" {
  // SELECT SUM(y) reads input y; the separately authored ORDER SUM(y) reads
  // the pre-group replacement alias y + 1. They must remain separate calls.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","derive":{"aql_group_key_0":{"add":[{"field":"y"},{"literal":1}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"x":{"fn":"sum","field":"y"},"aql_order_aggregate_0":{"fn":"sum","field":"aql_group_key_0"}}}},{"sort":[{"field":"aql_order_aggregate_0","dir":"asc","nulls":"first"}]},{"select":["x",{"y":"aql_group_key_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","y"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
    _ => fail("independent SELECT and ORDER aggregate inputs are closed")
  }
  for
    source in [
      "SELECT * REPLACE (SUM(y) AS x, y + 1 AS y) FROM t GROUP BY y ORDER BY SUM(y)",
      "SELECT SUM(y) AS x, y + 1 AS y FROM t GROUP BY y ORDER BY SUM(y)",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=source)
  }
}

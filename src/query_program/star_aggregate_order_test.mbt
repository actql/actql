///|
test "star replacement aggregate ORDER retains the SELECT input snapshot" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","derive":{"aql_group_key_0":{"add":[{"field":"y"},{"literal":1}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"x":{"fn":"sum","field":"y"}}}},{"select":["x",{"y":"aql_group_key_0"}]},{"sort":[{"field":"x","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","y"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
    _ => fail("the authored snapshot Program is closed")
  }
  for
    source in [
      "SELECT * REPLACE (SUM(y) AS x, y + 1 AS y) FROM t GROUP BY y ORDER BY x",
      "SELECT * REPLACE (SUM(y) AS x, y + 1 AS y) FROM t GROUP BY y ORDER BY `x`",
      "SELECT * REPLACE (SUM(y) AS `x`, y + 1 AS y) FROM t GROUP BY y ORDER BY x",
      "SELECT t.* REPLACE (SUM(t.y) AS x, t.y + 1 AS y) FROM t GROUP BY t.y + 1 ORDER BY `x`",
    ] {
    let generated = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(generated), semantic(expected), msg=source)
  }
}

///|
test "star replacement retains a colliding input beside a private ORDER aggregate" {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"aql_order_aggregate_0":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"aql_order_aggregate_0":1,"y":20},{"aql_order_aggregate_0":2,"y":10}]},"as":"t"}
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
        visible_fields: ["aql_order_aggregate_0", "y"],
        graph_bindings: [],
      },
    ],
  }
  let generated = compile(
    @query.parse_query(
      "SELECT * REPLACE (y + 0 AS y) FROM t GROUP BY 1, 2 ORDER BY COUNT(*) + 1, y",
      syntax_limits(),
    ).unwrap(),
    context,
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
    _ => fail("input identity and private aggregate are distinct slots")
  }
  assert_true(semantic(generated).contains("\"aql_having_aggregate_"))
}

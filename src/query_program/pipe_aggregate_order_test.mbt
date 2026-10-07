///|
test "Pipe aggregate shorthand ordering matches an independent checked Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","group":{"by":["x"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"bucket":"x"},"n"]},{"sort":[{"field":"bucket","dir":"asc","nulls":"first"}]},{"select":["bucket","n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["bucket","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ =>
      fail("the common group and sort accept the independent shorthand control")
  }
  let program = compile(
    @query.parse_query(
      "FROM pair |> AGGREGATE COUNT(*) AS n GROUP AND ORDER BY x AS bucket",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
}

///|
test "Pipe aggregate shorthand ordering puts suffixed keys before aggregate outputs" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","group":{"by":["x","y"],"aggregates":{"n":{"fn":"count"}}}},{"sort":[{"field":"y","dir":"desc","nulls":"last"},{"field":"n","dir":"asc","nulls":"first"}]},{"select":["x","y","n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","y","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ =>
      fail(
        "independent keyed and aggregate ordering uses existing checked slots",
      )
  }
  let program = compile(
    @query.parse_query(
      "FROM pair |> AGGREGATE COUNT(*) AS n ASC GROUP BY x, y DESC",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
}

///|
test "Pipe aggregate shorthand ordering never re-expands a renamed computed key" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","derive":{"aql_group_key_0":{"add":[{"field":"x"},{"literal":1}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"x":"aql_group_key_0"},"n"]},{"sort":[{"field":"x","dir":"desc","nulls":"last"}]},{"select":["x","n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the computed grouped slot is evaluated once")
  }
  let program = compile(
    @query.parse_query(
      "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 AS x DESC",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
}

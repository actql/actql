///|
test "independent range shadowing control is a checked object projection" {
  let control = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.range_shadow","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","derive":{"row":{"object":{"x":{"field":"x"},"y":{"field":"y"}}}}},{"select":["row"],"as":"out"}],"results":{"rows":{"from":"out","fields":["row"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(control, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    _ => fail("closed range-shadow control")
  }
}

///|
test "input range shadows a same-named ordinary column in SQL and Pipe" {
  for
    source in [
      "SELECT x AS row FROM pair AS x", "FROM pair |> AS x |> SELECT x AS row",
    ] {
    let p = match
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      ) {
      Ok(p) => p
      Err(UnknownColumn) => fail(source + ": UnknownColumn")
      Err(Expression(issue)) =>
        fail(source + ": " + @debug.to_string(issue.issue))
      Err(ExpressionTyping(issue)) =>
        fail(source + ": " + @debug.to_string(issue.kind))
      Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
      Err(_) => fail(source + ": other lowering refusal")
    }
    assert_true(
      semantic(p).contains(
        "\"object\":{\"x\":{\"field\":\"x\"},\"y\":{\"field\":\"y\"}}",
      ),
      msg=source,
    )
  }
}

///|
test "parenthesized input range does not become a same-named object column" {
  let p = compile(
    @query.parse_query(
      "FROM objects |> AS payload |> SELECT (payload).score AS value",
      syntax_limits(),
    ).unwrap(),
    pipe_range_property_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(p).contains("\"field\":\"score\"") &&
    !semantic(p).contains("\"field\":\"payload\""),
    msg="range score must read the original score column, not payload.score",
  )
}

///|
test "ORDER uses the original row while its current column is shadowed" {
  let p = compile(
    @query.parse_query(
      "FROM pair |> AS x |> SELECT y AS value |> ORDER BY COALESCE(x,NULL).x",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  match @check.check_parsed(p, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    _ => fail("closed row ORDER")
  }
  assert_true(
    semantic(p).contains(
      "\"object\":{\"x\":{\"field\":\"x\"},\"y\":{\"field\":\"y\"}}",
    ),
  )
}

///|
test "ORDER output alias overrides the same-named input row" {
  let p = compile(
    @query.parse_query(
      "SELECT y AS x FROM pair AS x ORDER BY x + 1",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(p).contains("\"add\":[{\"field\":\"y\"},{\"literal\":1}]"),
  )
  match @check.check_parsed(p, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    _ => fail("closed alias ORDER")
  }
}

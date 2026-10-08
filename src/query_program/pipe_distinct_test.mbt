///|
test "Pipe DISTINCT matches an independent visible-row Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","distinct":["x","y"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","y"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("visible-row DISTINCT uses the existing common operation")
  }
  let actual = compile(
    @query.parse_query("FROM pair |> DISTINCT", syntax_limits()).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "Pipe DISTINCT preserves surviving ranges and prunes displaced slots" {
  for
    source in [
      "FROM pair AS t |> DISTINCT |> WHERE t.x > 0 |> SELECT t.x AS x", "FROM pair AS t |> RENAME x AS z |> DISTINCT |> SELECT t.x AS old_x, z, t.y AS y",
      "FROM pair AS t |> DROP x |> DISTINCT |> SELECT t.y AS y", "FROM pair AS t |> SET x = y |> DISTINCT |> SELECT x, t.y AS y",
      "FROM pair |> AS old |> AS current |> DISTINCT |> SELECT current.x AS x", "FROM pair |> SELECT x AS y |> DISTINCT |> ORDER BY y + 1 |> SELECT y",
      "SELECT x FROM pair |> DISTINCT |> WHERE x > 0", "FROM pair |> SELECT x |> UNION ALL (FROM pair |> SELECT x) |> DISTINCT |> ORDER BY x",
      "WITH chosen AS (FROM pair AS t |> DISTINCT |> SELECT t.x AS x) SELECT x FROM chosen",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("Pipe DISTINCT adds no acquisition")
    }
  }
  for
    source in [
      "FROM pair AS t |> SET x = y |> DISTINCT |> SELECT t.x", "FROM pair AS t |> DROP x |> DISTINCT |> SELECT t.x",
      "FROM pair |> AS old |> AS current |> DISTINCT |> SELECT old.x", "FROM pair AS t |> SELECT DISTINCT * |> DISTINCT |> SELECT t.x",
      "FROM pair AS t |> SELECT x |> DISTINCT |> SELECT t.x",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: UnknownReference, .. })),
      msg=source,
    )
  }
}

///|
test "Pipe DISTINCT projects private slots before equality without re-evaluation" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","derive":{"aql_pipe_set_2":{"field":"y"}}},{"distinct":["aql_pipe_set_2","y"]},{"select":[{"x":"aql_pipe_set_2"},"y"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","y"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile(
    @query.parse_query(
      "FROM pair AS t |> SET x = y |> DISTINCT",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("Pipe DISTINCT uses only evaluated visible slots")
  }
}

///|
test "Pipe DISTINCT carries only surviving values into a subsequent JOIN" {
  for
    source in [
      "FROM t AS l |> DISTINCT |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> SELECT l.x AS x",
      "FROM t AS l |> SET y = x |> DISTINCT |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> SELECT y AS y, l.x AS original",
      "FROM t AS l |> DROP y |> DISTINCT |> JOIN r AS rr ON l.x = rr.k MAX_OUTPUT_ROWS 10 |> SELECT l.x AS x",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("DISTINCT JOIN prefix retains its existing producer")
    }
  }
}

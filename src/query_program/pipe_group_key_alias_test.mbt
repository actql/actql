///|
test "Pipe grouping-key aliases match an independent checked Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","group":{"by":["x"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"bucket":"x"},"n"]},{"select":["bucket","n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["bucket","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ =>
      fail("common group/projection accepts the independent key alias control")
  }
  for
    source in [
      "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x AS bucket", "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x bucket",
      "FROM pair AS input |> AGGREGATE COUNT(*) AS n GROUP BY input.x AS `bucket`",
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(expected))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ =>
        fail(
          "the Frontend retains the ordinary grouping and projection contract",
        )
    }
  }
}

///|
test "Pipe grouping-key aliases cannot redirect sibling input keys" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","group":{"by":["x","y"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"y":"x"},{"original_y":"y"},"n"]},{"select":["y","original_y","n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["y","original_y","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("each key retains the pre-group input scope")
  }
  let program = compile(
    @query.parse_query(
      "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x AS y, y AS original_y",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
}

///|
test "Pipe grouping-key aliases retain repeated physical keys" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","group":{"by":["x","x"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"first":"x"},{"second":"x"},"n"]},{"select":["first","second","n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["first","second","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("a repeated key does not invent rows or uniqueness")
  }
  let program = compile(
    @query.parse_query(
      "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x AS first, x AS second",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
}

///|
test "Pipe grouping-key aliases reject collisions and discarded names" {
  for
    source in [
      "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x AS n", "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x AS bucket, y AS `BUCKET`",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      )
      is Err(DuplicateOutput),
    )
  }
  for
    source in [
      "FROM pair |> AGGREGATE COUNT(*) AS n GROUP BY x AS bucket |> SELECT x", "FROM pair AS old |> AGGREGATE COUNT(*) AS n GROUP BY old.x AS bucket |> SELECT old.x",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: UnknownReference, .. })),
    )
  }
}

///|
test "Pipe grouping-only AGGREGATE matches an independent checked Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","group":{"by":["x"],"aggregates":{}}},{"select":["x"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the ordinary group contract accepts an empty aggregate map")
  }
  for
    source in [
      "FROM pair |> AGGREGATE GROUP BY x", "FROM pair AS original |> AGGREGATE GROUP BY original.x",
      "FROM pair |> AGGREGATE GROUP BY `x`",
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
      _ => fail("the Frontend preserves the ordinary group contract")
    }
  }
}

///|
test "Pipe grouping-only AGGREGATE closes input ranges" {
  let source = "FROM pair AS original |> AGGREGATE GROUP BY original.x |> SELECT original.x"
  assert_true(
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: UnknownReference, .. })),
  )
  let program = compile(
    @query.parse_query(
      "FROM pair |> AGGREGATE GROUP BY x |> WHERE x = 7 |> SELECT x",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("subsequent operations consume the grouped output")
  }
  assert_true(semantic(program).contains("\"fields\":[\"x\"]"))
}

///|
test "Pipe grouping-only AGGREGATE retains the explicit global group" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","group":{"by":[],"aggregates":{}}},{"derive":{"aql_pipe_extend_0":{"literal":1}}},{"select":[{"marker":"aql_pipe_extend_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["marker"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the common global group supports an empty output row")
  }
  let program = compile(
    @query.parse_query(
      "FROM pair |> AGGREGATE GROUP BY () |> EXTEND 1 AS marker",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
}

///|
// The common publication boundary is separate from global grouping semantics.
test "Pipe grouping-only AGGREGATE records the zero-column Result boundary" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[]},"as":"pair"},{"from":"pair","group":{"by":[],"aggregates":{}},"as":"global"}],"results":{"rows":{"from":"global","fields":[]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Rejected(error) => {
      guard @check.diagnostic_cause(error)
        is Source(SourceView(Program(Program(Results(_, issue))))) else {
        raise @check.diagnostic_cause(error)
      }
      assert_true(issue.kind is InvalidBody)
    }
    _ =>
      fail(
        "update this dependency record when zero-column publication is supported",
      )
  }
}

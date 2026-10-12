///|
fn source_range_control() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.source_range","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","derive":{"value":{"add":[{"field":"x"},{"literal":0}]}}},{"select":["value"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "independent source range Program uses the original column with ordinary addition" {
  assert_true(
    @check.check_parsed(
      source_range_control(),
      check_environment(),
      None,
      check_limits(),
    )
    is Checked(_),
  )
}

///|
test "ordinary SQL and unchanged Pipe bind parenthesized source range columns" {
  for
    text in [
      "SELECT ((p)).x + 0 AS value FROM pair p ORDER BY value", "FROM pair p |> SELECT ((p)).x + 0 AS value |> ORDER BY value",
      "SELECT ((`P`)).`X` + 0 AS value FROM pair `p` ORDER BY value",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      semantic(actual).contains("\"add\":[{\"field\":\"x\"},{\"literal\":0}]"),
    )
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}

///|
test "ordinary range binding preserves nested nullable and same-named value receivers" {
  let nested = compile(
    @query.parse_query(
      "SELECT ((o)).payload.score AS value FROM objects o",
      syntax_limits(),
    ).unwrap(),
    analytic_property_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(nested).contains(
      "\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}",
    ),
  )
  assert_true(
    @check.check_parsed(nested, check_environment(), None, check_limits())
    is Checked(_),
  )
  let value = compile(
    @query.parse_query(
      "SELECT (payload.payload).score AS value FROM objects payload",
      syntax_limits(),
    ).unwrap(),
    pipe_range_property_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(value).contains(
      "\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}",
    ),
  )
  assert_true(
    @check.check_parsed(value, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "ordinary range binding cannot capture private-looking input references" {
  let actual = compile(
    @query.parse_query(
      "SELECT ((o)).id + aql_pipe_range_property_0 AS value FROM objects o",
      syntax_limits(),
    ).unwrap(),
    pipe_range_property_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(actual).contains(
      "\"add\":[{\"field\":\"id\"},{\"field\":\"aql_pipe_range_property_0\"}]",
    ),
  )
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "ordinary range binding preserves exact unknown and bounded-work refusals" {
  for
    text in [
      "SELECT (missing).x AS value FROM pair p", "SELECT (p).missing AS value FROM pair p",
    ] {
    match compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ) {
      Err(Expression({ issue: UnknownReference, origin: Some(_), })) => ()
      Ok(program) => fail("Unexpected unresolved receiver Program: " + text + " " + semantic(program))
      Err(_) => fail("Unexpected unresolved receiver refusal: " + text)
    }
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT ((p)).x + 0 AS value FROM pair p",
        syntax_limits(),
      ).unwrap(),
      pair_context(),
      { ..construction_limits(), max_expression_work: 1, },
    )
    is Err(Expression({ issue: WorkLimit, origin: Some(_), })),
  )
}

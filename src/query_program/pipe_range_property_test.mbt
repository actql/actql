///|
fn pipe_range_property_context() -> Context {
  let seed =
    #|{"values":{"schema":{"id":{"type":"number","nullable":false},"score":{"type":"number","nullable":false},"payload":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}},"aql_pipe_range_property_0":{"type":"number","nullable":false}},"rows":[{"id":1,"score":90,"payload":{"score":10},"aql_pipe_range_property_0":100}]},"as":"objects"}
  {
    ..fixture_context(),
    inputs: [
      {
        relation: [{ value: "objects", quoted: false, }],
        name: "objects",
        source: GeneratedValues(unnest_value_cursor(seed)),
        visible_fields: ["id", "score", "payload", "aql_pipe_range_property_0"],
        graph_bindings: [],
      },
    ],
  }
}

///|
test "parenthesized range binding cannot capture an authored private-looking name" {
  let actual = compile(
    @query.parse_query(
      "FROM objects |> AS p |> SELECT (p).id + aql_pipe_range_property_0 AS value",
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
test "a parenthesized ordinary range keeps priority over an object column" {
  let actual = compile(
    @query.parse_query(
      "FROM objects |> AS payload |> SELECT (payload).score AS value",
      syntax_limits(),
    ).unwrap(),
    pipe_range_property_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    // The admitted input range binds the score column (90), not the
    // same-named payload column's score (10). Expectations follow the pin.
    semantic(actual).contains("\"field\":\"score\"") &&
    !semantic(actual).contains("\"field\":\"payload\""),
  )
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "parenthesized removed ranges cannot manufacture a column" {
  assert_true(
    compile(
      @query.parse_query(
        "FROM objects p |> SELECT id |> WHERE (p).id > 0",
        syntax_limits(),
      ).unwrap(),
      pipe_range_property_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: UnknownReference, origin: Some(_), })),
  )
}

///|
test "missing member of an ordinary row is refused by the existing property checker" {
  let p = compile(
    @query.parse_query(
      "SELECT (p).missing AS value FROM objects p",
      syntax_limits(),
    ).unwrap(),
    pipe_range_property_context(),
    construction_limits(),
  ).unwrap()
  guard @check.check_parsed(p, check_environment(), None, check_limits())
    is Rejected(issue) else {
    fail("unknown row property accepted")
  }
  assert_true(
    @check.diagnostic_cause(issue)
    is Source(
      SourceView(
        Program(
          Program(
            Pipeline(
              _,
              { kind: Operation(Expression(UnknownField("missing"))), .. }
            )
          )
        )
      )
    ),
  )
}

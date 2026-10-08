///|
fn object_star_control() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":10},"other":{"score":30}},{"id":1,"payload":{"score":20},"other":{"score":5}},{"id":3,"payload":null,"other":{"score":15}}]},"as":"objects"},{"from":"objects","derive":{"aql_query_expr_1":{"property":{"value":{"field":"payload"},"name":"score"}}}},{"select":["id",{"score":"aql_query_expr_1"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","score"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "object column star control uses common nullable property typing" {
  assert_true(
    @check.check_parsed(
      object_star_control(),
      check_environment(),
      None,
      check_limits(),
    )
    is Checked(_),
  )
}

///|
test "object column star lowers to an independent property projection" {
  for
    text in [
      "SELECT id, payload.* FROM objects", "SELECT id, objects.payload.* FROM objects",
      "FROM objects |> SELECT id, payload.*",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      analytic_property_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(object_star_control()), msg=text)
  }
}

///|
test "object column star preserves SET current values and retained range values" {
  for
    text in [
      "FROM objects o |> SET payload = other |> SELECT id, payload.*", "FROM objects o |> SET payload = other |> SELECT id, o.payload.*",
      "SELECT payload.*, COUNT(*) AS n FROM objects GROUP BY payload.score ORDER BY score",
      "SELECT id, payload.* EXCEPT (score) FROM objects", "SELECT id, payload.* REPLACE ('changed' AS score) FROM objects",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      analytic_property_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
      msg=text,
    )
    assert_false(semantic(actual).contains("aql_object_star_probe_"))
  }
}

///|
test "object column star retains exact absent range scalar and replacement refusals" {
  for
    text in [
      "SELECT id.* FROM objects", "FROM objects o |> AS current |> SELECT o.*", "FROM objects |> SELECT id |> SELECT payload.*",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        analytic_property_context(),
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=text,
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT payload.* EXCEPT (missing) FROM objects",
        syntax_limits(),
      ).unwrap(),
      analytic_property_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT payload.* REPLACE (1 AS score, 2 AS SCORE) FROM objects",
        syntax_limits(),
      ).unwrap(),
      analytic_property_context(),
      construction_limits(),
    )
    is Err(DuplicateOutput),
  )
}

///|
test "object column star reads canonical declared fields on empty input within work limits" {
  let seed = unnest_value_cursor(
    (
      #|{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"z":{"type":"number","nullable":false},"a":{"type":"string","nullable":true}}}},"rows":[]},"as":"objects"}
    ),
  )
  let context : Context = {
    ..analytic_property_context(),
    inputs: [
      {
        relation: [{ value: "objects", quoted: false, }],
        name: "objects",
        source: GeneratedValues(seed),
        visible_fields: ["id", "payload"],
        graph_bindings: [],
      },
    ],
  }
  let query = @query.parse_query(
    "SELECT id, payload.* FROM objects",
    syntax_limits(),
  ).unwrap()
  let actual = compile(query, context, construction_limits()).unwrap()
  assert_true(semantic(actual).contains("\"fields\":[\"id\",\"a\",\"z\"]"))
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Checked(_),
  )
  assert_true(
    compile(query, context, { ..construction_limits(), max_expression_work: 1, })
    is Err(Expression({ issue: WorkLimit, .. })),
  )
}

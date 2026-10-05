///|
fn aggregate_property_context() -> Context {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"number","nullable":false},"bucket":{"type":"string","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"bucket":"A","payload":{"score":10},"other":{"score":100}},{"id":1,"bucket":"A","payload":{"score":20},"other":{"score":200}},{"id":3,"bucket":"A","payload":null,"other":{"score":300}},{"id":5,"bucket":"A","payload":{"score":20},"other":{"score":400}},{"id":6,"bucket":"A","payload":{"score":30},"other":{"score":500}},{"id":4,"bucket":"B","payload":{"score":null},"other":{"score":600}}]},"as":"objects"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..pair_context(),
    inputs: [
      {
        relation: [{ value: "objects", quoted: false, }],
        name: "objects",
        source: GeneratedValues(seed),
        visible_fields: ["id", "bucket", "payload", "other"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn checked_aggregate_property(text : String) -> @program.Program raise {
  let program = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    aggregate_property_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("typed Values use existing expression and numeric contracts")
  }
  program
}

///|
test "aggregate property paths lower SQL nullable receivers" {
  let program = checked_aggregate_property(
    "SELECT COUNT(payload.score) AS n, MIN(objects.payload.score) AS m FROM objects",
  )
  assert_true(
    semantic(program).contains(
      "\"expr\":{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}}",
    ),
  )
}

///|
test "aggregate property paths lower Pipe nullable receivers" {
  let program = checked_aggregate_property(
    "FROM objects AS before |> AGGREGATE COUNT(before.payload.score) AS n, MIN(payload.score) AS m |> SELECT n, m",
  )
  assert_true(semantic(program).contains("\"expr\":{\"property\""))
}

///|
test "aggregate property paths match an independent complete Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"bucket":{"type":"string","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"bucket":"A","payload":{"score":10},"other":{"score":100}},{"id":1,"bucket":"A","payload":{"score":20},"other":{"score":200}},{"id":3,"bucket":"A","payload":null,"other":{"score":300}},{"id":5,"bucket":"A","payload":{"score":20},"other":{"score":400}},{"id":6,"bucket":"A","payload":{"score":30},"other":{"score":500}},{"id":4,"bucket":"B","payload":{"score":null},"other":{"score":600}}]},"as":"objects"},{"from":"objects","group":{"by":[],"aggregates":{"n":{"fn":"count","expr":{"property":{"value":{"field":"payload"},"name":"score"}}},"m":{"fn":"min","expr":{"property":{"value":{"field":"payload"},"name":"score"}}}}}},{"select":["n","m"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["n","m"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
    msg="the existing common group supports the independent property expression",
  )
  for
    text in [
      "SELECT COUNT(payload.score) AS n, MIN(objects.payload.score) AS m FROM objects",
      "FROM objects AS before |> AGGREGATE COUNT(before.payload.score) AS n, MIN(payload.score) AS m |> SELECT n, m",
    ] {
    assert_eq(semantic(checked_aggregate_property(text)), semantic(expected))
  }
}

///|
test "aggregate property paths preserve computed arguments and numeric evidence" {
  let query = @query.parse_query(
    "SELECT bucket, COUNT(DISTINCT payload.score) AS n, COUNTIF(payload.score > 10) AS positive, SUM(objects.payload.score + 1) AS total, AVG(payload.score) AS mean, MAX(`payload`.`score`) AS hi FROM objects GROUP BY bucket ORDER BY bucket",
    syntax_limits(),
  ).unwrap()
  let program = compile(
    query,
    aggregate_property_context(),
    construction_limits(),
  ).unwrap()
  assert_true(semantic(program).contains("\"distinct\":true"))
  assert_true(semantic(program).contains("\"property\""))
  assert_true(
    @check.check_parsed(program, check_environment(), None, check_limits())
    is NeedsInputs(_),
    msg="Frontend cannot invent the required numeric observation profile",
  )
  assert_true(
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      None,
      check_limits(),
    )
    is Checked(_),
  )
}

///|
test "aggregate property paths keep current and immutable Pipe receivers separate" {
  let program = checked_aggregate_property(
    "FROM objects AS before |> SET payload = other |> AGGREGATE COUNT(payload.score) AS current_count, COUNT(before.payload.score) AS original_count",
  )
  let body = semantic(program)
  assert_true(
    body.contains(
      "\"property\":{\"name\":\"score\",\"value\":{\"field\":\"aql_pipe_set_4\"}}",
    ),
  )
  assert_true(
    body.contains(
      "\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}",
    ),
  )
  assert_true(
    !body.contains("\"derive\":{\"original_count\""),
    msg="argument evaluation belongs to the aggregate owner, not a preceding derive",
  )
}

///|
test "aggregate property paths share the limited OVER argument boundary" {
  let program = checked_aggregate_property(
    "SELECT id, COUNT(payload.score) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running FROM objects ORDER BY id",
  )
  assert_true(semantic(program).contains("\"expr\":{\"property\""))
}

///|
test "aggregate property paths retain scope and common field type refusals" {
  for
    text in [
      "SELECT COUNT(payload.missing) AS n FROM objects", "SELECT COUNT(id.score) AS n FROM objects",
      "SELECT COUNTIF(payload.score) AS n FROM objects",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      aggregate_property_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Rejected(_),
      msg="common typing rejects invalid aggregate property arguments",
    )
  }
  match
    compile(
      @query.parse_query(
        "FROM objects AS old |> AS current |> AGGREGATE COUNT(old.payload.score) AS n",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_context(),
      construction_limits(),
    ) {
    Err(Expression({ issue: UnknownReference, .. })) => ()
    _ => fail("a displaced Pipe range cannot recover its old object")
  }
}

///|
test "aggregate property paths retain bounded work and original diagnostics" {
  let query = @query.parse_query(
    "SELECT COUNT(payload.score) AS n FROM objects",
    syntax_limits(),
  ).unwrap()
  match
    compile(query, aggregate_property_context(), {
      ..construction_limits(),
      max_expression_work: 1,
    }) {
    Err(Expression({ issue: WorkLimit, origin: Some(_), })) => ()
    _ => fail("property prefix work is charged with its original query origin")
  }
}

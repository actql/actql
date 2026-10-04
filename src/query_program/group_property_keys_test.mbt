///|
fn group_property_context() -> Context {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":10},"other":{"score":100}},{"id":1,"payload":{"score":20},"other":{"score":200}},{"id":3,"payload":null,"other":{"score":300}},{"id":4,"payload":{"score":20},"other":{"score":400}},{"id":5,"payload":{"score":null},"other":{"score":500}}]},"as":"objects"}
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
        visible_fields: ["id", "payload", "other"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn checked_group_property(text : String) -> @program.Program raise {
  let program = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    group_property_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("group keys use the common typed property and grouping contracts")
  }
  program
}

///|
fn independent_group_property_program() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":10},"other":{"score":100}},{"id":1,"payload":{"score":20},"other":{"score":200}},{"id":3,"payload":null,"other":{"score":300}},{"id":4,"payload":{"score":20},"other":{"score":400}},{"id":5,"payload":{"score":null},"other":{"score":500}}]},"as":"objects"},{"from":"objects","derive":{"aql_group_key_0":{"property":{"name":"score","value":{"field":"payload"}}}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"score":"aql_group_key_0"},"n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["score","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "GROUP property keys have an independent checked Program" {
  match
    @check.check_parsed(
      independent_group_property_program(),
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ =>
      fail("existing derive and group already express nullable property keys")
  }
}

///|
test "GROUP property keys lower SQL nullable receivers" {
  let program = checked_group_property(
    "SELECT payload.score AS score, COUNT(*) AS n FROM objects GROUP BY payload.score",
  )
  assert_eq(semantic(program), semantic(independent_group_property_program()))
}

///|
test "GROUP property keys lower qualified Pipe receivers" {
  let program = checked_group_property(
    "FROM objects AS before |> AGGREGATE COUNT(*) AS n GROUP BY before.payload.score",
  )
  assert_true(
    semantic(program).contains(
      "\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}",
    ),
  )
  assert_true(semantic(program).contains("\"fields\":[\"score\",\"n\"]"))
}

///|
test "GROUP property keys reuse resolved input meanings across SELECT spellings" {
  for
    source in [
      "SELECT objects.payload.score AS score, COUNT(*) AS n FROM objects GROUP BY payload.score",
      "SELECT payload.score AS score, COUNT(*) AS n FROM objects GROUP BY objects.payload.score",
      "SELECT `objects`.`payload`.`score` AS score, COUNT(*) AS n FROM objects GROUP BY score",
      "SELECT payload.score AS score, COUNT(*) AS n FROM objects GROUP BY 1",
    ] {
    let body = semantic(checked_group_property(source))
    assert_eq(
      body.split("\"property\":").length(),
      2,
      msg="the selected key is evaluated once, before grouping",
    )
    assert_true(body.contains("\"fields\":[\"score\",\"n\"]"))
  }
}

///|
test "GROUP property keys retain qualified references inside computed keys" {
  let program = checked_group_property(
    "SELECT objects.payload.score + 1 AS next, COUNT(*) AS n FROM objects GROUP BY payload.score + 1 HAVING next > 10 ORDER BY next",
  )
  let body = semantic(program)
  assert_eq(body.split("\"property\":").length(), 2)
  assert_eq(body.split("\"add\":").length(), 2)
  assert_true(body.contains("\"fields\":[\"next\",\"n\"]"))
}

///|
test "GROUP property keys separate current SET values and old range snapshots" {
  for
    (reference, field) in [
      ("payload.score", "aql_pipe_set_3"),
      ("before.payload.score", "payload"),
    ] {
    let program = checked_group_property(
      "FROM objects AS before |> SET payload = other |> AGGREGATE COUNT(*) AS n GROUP BY " +
      reference,
    )
    assert_true(
      semantic(program).contains(
        "\"property\":{\"name\":\"score\",\"value\":{\"field\":\"" +
        field +
        "\"}}",
      ),
    )
  }
}

///|
test "GROUP property keys cannot revive ungrouped receivers or displaced aliases" {
  for
    source in [
      "SELECT other.score AS score, COUNT(*) AS n FROM objects GROUP BY payload.score",
      "SELECT payload AS value, COUNT(*) AS n FROM objects GROUP BY payload.score",
      "FROM objects AS old |> AS current |> AGGREGATE COUNT(*) AS n GROUP BY old.payload.score",
      "FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY payload.score |> SELECT payload.score",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        group_property_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: UnknownReference, .. })),
      msg=source,
    )
  }
}

///|
test "GROUP property keys keep field typing with the common checker" {
  for
    source in [
      "SELECT COUNT(*) AS n FROM objects GROUP BY payload.missing", "SELECT COUNT(*) AS n FROM objects GROUP BY id.score",
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      group_property_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Rejected(_),
      msg=source,
    )
  }
}

///|
test "GROUP property keys charge receiver resolution with original diagnostics" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT COUNT(*) AS n FROM objects GROUP BY payload.score",
        syntax_limits(),
      ).unwrap(),
      group_property_context(),
      { ..construction_limits(), max_expression_work: 1, },
    )
    is Err(Expression({ issue: WorkLimit, origin: Some(_), })),
  )
}

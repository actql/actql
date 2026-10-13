///|
// Independent SQL control plus the existing final Pipe visibility projection.
// The extra identity projection changes structure, not grouping values or names.
fn independent_pipe_member_group_program() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":10},"other":{"score":100}},{"id":1,"payload":{"score":20},"other":{"score":200}},{"id":3,"payload":null,"other":{"score":300}},{"id":4,"payload":{"score":20},"other":{"score":400}},{"id":5,"payload":{"score":null},"other":{"score":500}}]},"as":"objects"},{"from":"objects","derive":{"aql_group_key_0":{"property":{"name":"score","value":{"field":"payload"}}}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"score":"aql_group_key_0"},"n"]},{"select":["score","n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["score","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Pipe GROUP property member aliases match the independent checked Program" {
  let sql_expected = independent_group_property_program()
  let pipe_expected = independent_pipe_member_group_program()
  for expected in [sql_expected, pipe_expected] {
    match
      @check.check_parsed(expected, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("ordinary property, group and projection express this contract")
    }
  }
  for
    source in [
      "FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY (payload).score", "FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY (objects.payload).score",
      "FROM objects AS before |> AGGREGATE COUNT(*) AS n GROUP BY (before.payload).score",
      "FROM objects AS before |> AGGREGATE COUNT(*) AS n GROUP BY (before.`payload`).`score`",
      "SELECT (payload).score, COUNT(*) AS n FROM objects GROUP BY (payload).score",
    ] {
    let expected = if source.has_prefix("SELECT") {
      sql_expected
    } else {
      pipe_expected
    }
    assert_eq(semantic(checked_group_property(source)), semantic(expected))
  }
}

///|
test "Pipe GROUP property member aliases become visible to later operations" {
  let program = checked_group_property(
    "FROM objects |> AGGREGATE COUNT(*) AS n GROUP BY (payload).score |> WHERE score IS NOT NULL |> ORDER BY score DESC |> SELECT score, n",
  )
  let body = semantic(program)
  assert_true(body.contains("\"fields\":[\"score\",\"n\"]"))
  assert_true(body.contains("\"field\":\"score\",\"nulls\":\"last\""))
  assert_true(body.contains("\"field\":\"score\""))
  assert_eq(body.split("\"property\":").length(), 2)
}

///|
test "Pipe GROUP property member aliases retain collisions and removed scopes" {
  match
    compile(
      @query.parse_query(
        "FROM objects |> AGGREGATE COUNT(*) AS score GROUP BY (payload).score",
        syntax_limits(),
      ).unwrap(),
      group_property_context(),
      construction_limits(),
    ) {
    Err(DuplicateOutput) => ()
    _ => fail("grouping and aggregate leaf names cannot silently collide")
  }
  for
    source in [
      "FROM objects AS old |> AS `current` |> AGGREGATE COUNT(*) AS n GROUP BY (old.payload).score",
      "FROM objects AS old |> AGGREGATE COUNT(*) AS n GROUP BY (old.payload).score |> SELECT old.payload.score",
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

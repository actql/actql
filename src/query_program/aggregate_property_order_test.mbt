///|
fn aggregate_property_order_seed() -> String {
  (
    #|{"values":{"schema":{"id":{"type":"number","nullable":false},"name":{"type":"string","nullable":true},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"name":"b","payload":{"score":10},"other":{"score":30}},{"id":1,"name":"a","payload":{"score":20},"other":{"score":5}},{"id":3,"name":"c","payload":null,"other":{"score":15}},{"id":4,"name":null,"payload":{"score":null},"other":{"score":25}}]},"as":"objects"}
  )
}

///|
fn aggregate_property_order_context() -> Context {
  let seed = @wire.admit(
    @source.parse_json(
      aggregate_property_order_seed(),
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
        visible_fields: ["id", "name", "payload", "other"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn aggregate_property_order_expected() -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    aggregate_property_order_seed() +
    (
      #|,{"from":"objects","derive":{"aql_aggregate_sort_5":{"property":{"name":"score","value":{"field":"payload"}}}}},{"group":{"by":[],"aggregates":{"names":{"fn":"string_agg","field":"name","max_bytes":10000,"order_by":[{"field":"aql_aggregate_sort_5","dir":"asc","nulls":"last"},{"field":"id","dir":"asc","nulls":"first"}],"delimiter":"|"}}}},{"select":["names"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["names"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "aggregate property ORDER has a checked independent Program and source counterpart" {
  let expected = aggregate_property_order_expected()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) =>
      match @check.diagnostic_cause(error) {
        Source(cause) => raise cause
        cause => raise cause
      }
    _ => fail("the existing common owner accepts the authored property order")
  }
  let actual = match
    compile(
      @query.parse_query(
        "SELECT STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names FROM objects",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnknownColumn) => fail("UnknownColumn")
    Err(_) => fail("unexpected lowering rejection")
  }
  assert_eq(semantic(actual), semantic(expected))
}

///|
fn checked_aggregate_property_order(text : String) -> @program.Program raise {
  let actual = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    aggregate_property_order_context(),
    construction_limits(),
  ).unwrap()
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) =>
      match @check.diagnostic_cause(error) {
        Source(cause) => raise cause
        cause => raise cause
      }
    _ => fail("aggregate ordering uses the common type and order checker")
  }
  actual
}

///|
test "aggregate property ORDER preserves qualified quoted and parenthesized receivers" {
  let expected = semantic(aggregate_property_order_expected())
  for
    text in [
      "SELECT STRING_AGG(name, '|' ORDER BY objects.payload.score NULLS LAST, id) AS names FROM objects",
      "FROM objects AS before |> AGGREGATE STRING_AGG(name, '|' ORDER BY `before`.`payload`.`score` NULLS LAST, id) AS names",
      "SELECT STRING_AGG(name, '|' ORDER BY (payload.score) NULLS LAST, id) AS names FROM objects",
    ] {
    assert_eq(semantic(checked_aggregate_property_order(text)), expected)
  }
}

///|
test "aggregate property ORDER preserves ARRAY item keys through an explicit existing assertion" {
  let body = semantic(
    checked_aggregate_property_order(
      "FROM objects |> ASSERT UNIQUE BY (id) |> AGGREGATE ARRAY_AGG(id IGNORE NULLS ORDER BY payload.score NULLS LAST, id) AS ids",
    ),
  )
  assert_true(body.contains("\"unique_by\":[\"id\"]"))
  assert_true(body.contains("\"fn\":\"array_agg\""))
  assert_true(body.contains("\"value\":{\"field\":\"payload\"}"))
  assert_true(body.contains("\"fields\":[\"ids\"]"))
}

///|
test "aggregate property ORDER shares total projections while retaining per-call order" {
  let body = semantic(
    checked_aggregate_property_order(
      "SELECT STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names, STRING_AGG(name, '|' ORDER BY payload.score DESC NULLS FIRST, id) AS reverse FROM objects",
    ),
  )
  assert_eq(body.split("\"property\":").length(), 2)
  assert_true(
    body.contains(
      "\"dir\":\"asc\",\"field\":\"aql_aggregate_sort_6\",\"nulls\":\"last\"",
    ),
  )
  assert_true(
    body.contains(
      "\"dir\":\"desc\",\"field\":\"aql_aggregate_sort_6\",\"nulls\":\"first\"",
    ),
  )
  assert_true(body.contains("\"fields\":[\"names\",\"reverse\"]"))
}

///|
test "aggregate property ORDER resolves SET current slots and immutable range snapshots" {
  let body = semantic(
    checked_aggregate_property_order(
      "FROM objects AS before |> SET payload = other |> AGGREGATE STRING_AGG(name, '|' ORDER BY payload.score, id) AS current, STRING_AGG(name, '|' ORDER BY before.payload.score NULLS LAST, id) AS previous",
    ),
  )
  assert_true(body.contains("\"value\":{\"field\":\"aql_pipe_set_4\"}"))
  assert_true(body.contains("\"value\":{\"field\":\"payload\"}"))
  assert_true(body.contains("\"fields\":[\"current\",\"previous\"]"))
}

///|
test "aggregate property ORDER uses input scope and does not hoist demanded arguments" {
  let body = semantic(
    checked_aggregate_property_order(
      "SELECT COUNT(*) AS payload, STRING_AGG(IF(id / (id - id) = 0, name, name), '|' ORDER BY payload.score, id) AS names FROM objects",
    ),
  )
  assert_true(body.contains("\"value\":{\"field\":\"payload\"}"))
  assert_true(body.contains("\"expr\":{\"if\":"))
  assert_eq(body.split("\"derive\":").length(), 2)
  assert_true(body.contains("\"fields\":[\"payload\",\"names\"]"))
}

///|
test "aggregate property ORDER preserves exact scope refusals and common member typing" {
  for
    text in [
      "FROM objects AS old |> AS current |> AGGREGATE STRING_AGG(name, '|' ORDER BY old.payload.score, id) AS names",
      "SELECT STRING_AGG(name, '|' ORDER BY names, id) AS names FROM objects",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        aggregate_property_order_context(),
        construction_limits(),
      )
      is Err(UnknownColumn),
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT STRING_AGG(name, '|' ORDER BY id + 1) AS names FROM objects",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    )
    is Err(UnsupportedAggregate),
  )
  for reference in ["payload.missing", "id.score"] {
    let program = compile(
      @query.parse_query(
        "SELECT STRING_AGG(name, '|' ORDER BY " +
        reference +
        ", id) AS names FROM objects",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Rejected(_),
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT STRING_AGG(name, '|' ORDER BY payload.score, id) AS names FROM objects",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      { ..construction_limits(), max_expression_work: 1, },
    )
    is Err(Expression({ issue: WorkLimit, origin: Some(_), })),
  )
}

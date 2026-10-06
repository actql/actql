///|
fn partition_property_seed() -> String {
  (
    #|{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"bucket":{"type":"string","nullable":true}}},"other":{"type":"object","nullable":false,"fields":{"bucket":{"type":"string","nullable":false}}}},"rows":[{"id":4,"payload":{"bucket":"A"},"other":{"bucket":"B"}},{"id":1,"payload":{"bucket":"B"},"other":{"bucket":"B"}},{"id":3,"payload":null,"other":{"bucket":"A"}},{"id":2,"payload":{"bucket":"A"},"other":{"bucket":"A"}},{"id":5,"payload":{"bucket":null},"other":{"bucket":"B"}}]},"as":"objects"}
  )
}

///|
fn partition_property_context() -> Context {
  let seed = @wire.admit(
    @source.parse_json(
      partition_property_seed(),
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
fn partition_property_expected() -> @program.Program {
  // The ordinary Program is authored independently of the source compiler.
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    partition_property_seed() +
    (
      #|,{"from":"objects","derive":{"aql_analytic_sort_4":{"property":{"name":"bucket","value":{"field":"payload"}}}}},{"analytic":{"partition_by":["aql_analytic_sort_4"],"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"functions":{"pos":{"fn":"row_number"}}}},{"select":["id","pos"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","pos"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn checked_partition_property(text : String) -> @program.Program raise {
  let program = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    partition_property_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("partition paths use the existing closed key contract")
  }
  program
}

///|
test "analytic partition properties keep immutable SELECT input receivers" {
  for
    text in [
      "SELECT other AS payload, ROW_NUMBER() OVER (PARTITION BY payload.bucket ORDER BY id) AS pos FROM objects",
      "SELECT other AS payload, ROW_NUMBER() OVER (PARTITION BY objects.payload.`bucket` ORDER BY id) AS pos FROM objects",
    ] {
    let wire = semantic(checked_partition_property(text))
    assert_true(
      wire.contains(
        "\"property\":{\"name\":\"bucket\",\"value\":{\"field\":\"payload\"}}",
      ),
    )
    assert_true(!wire.contains("\"value\":{\"field\":\"other\"}"))
  }
}

///|
test "analytic partition properties preserve current and Pipe snapshot slots" {
  let wire = semantic(
    checked_partition_property(
      "FROM objects AS original |> SET payload = other |> SELECT id, ROW_NUMBER() OVER (PARTITION BY original.payload.bucket ORDER BY id) AS before, ROW_NUMBER() OVER (PARTITION BY payload.bucket ORDER BY id) AS current |> ORDER BY id",
    ),
  )
  assert_true(wire.contains("\"value\":{\"field\":\"payload\"}"))
  assert_true(wire.contains("\"value\":{\"field\":\"aql_pipe_set_3\"}"))
  assert_eq(wire.split("\"analytic\":").length(), 3)
}

///|
test "analytic partition properties share evaluation and retain repeated keys" {
  let wire = semantic(
    checked_partition_property(
      "SELECT id, ROW_NUMBER() OVER (PARTITION BY payload.bucket, payload.bucket ORDER BY payload.bucket, id) AS pos, RANK() OVER (PARTITION BY payload.bucket, payload.bucket ORDER BY payload.bucket, id) AS ranking FROM objects ORDER BY id",
    ),
  )
  assert_eq(wire.split("\"property\":").length(), 2)
  assert_true(
    wire.contains(
      "\"partition_by\":[\"aql_analytic_sort_5\",\"aql_analytic_sort_5\"]",
    ),
  )
  assert_eq(wire.split("\"analytic\":").length(), 2)
}

///|
test "analytic partition properties preserve typed scope refusals and work bounds" {
  for
    text in [
      "SELECT ROW_NUMBER() OVER (PARTITION BY missing.bucket ORDER BY id) AS pos FROM objects",
      "SELECT other AS sibling, ROW_NUMBER() OVER (PARTITION BY sibling.bucket ORDER BY id) AS pos FROM objects",
      "FROM objects AS old |> AS current |> SELECT ROW_NUMBER() OVER (PARTITION BY old.payload.bucket ORDER BY id) AS pos",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        partition_property_context(),
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=text,
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT ROW_NUMBER() OVER (PARTITION BY payload.bucket ORDER BY id) AS pos FROM objects",
        syntax_limits(),
      ).unwrap(),
      partition_property_context(),
      { ..construction_limits(), max_expression_work: 1, },
    )
    is Err(Expression({ issue: @expression.WorkLimit, .. })),
  )
}

///|
test "analytic partition properties delegate member and key types to the checker" {
  for path in ["payload.missing", "id.bucket", "payload"] {
    let program = compile(
      @query.parse_query(
        "SELECT ROW_NUMBER() OVER (PARTITION BY " +
        path +
        " ORDER BY id) AS pos FROM objects",
        syntax_limits(),
      ).unwrap(),
      partition_property_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Rejected(_),
      msg="Frontend must not invent a member or a groupable object key: " + path,
    )
  }
}

///|
test "analytic partition properties match an independent checked Program" {
  let expected = partition_property_expected()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent nullable partition Program must be closed")
  }
  for
    text in [
      "SELECT id, ROW_NUMBER() OVER (PARTITION BY payload.bucket ORDER BY id) AS pos FROM objects ORDER BY id",
      "FROM objects |> SELECT id, ROW_NUMBER() OVER (PARTITION BY payload.bucket ORDER BY id) AS pos |> ORDER BY id",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      partition_property_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(expected))
  }
}

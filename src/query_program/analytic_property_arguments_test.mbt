///|
fn analytic_property_context() -> Context {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":10},"other":{"score":30}},{"id":1,"payload":{"score":20},"other":{"score":5}},{"id":3,"payload":null,"other":{"score":15}}]},"as":"objects"}
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
fn analytic_property_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":10},"other":{"score":30}},{"id":1,"payload":{"score":20},"other":{"score":5}},{"id":3,"payload":null,"other":{"score":15}}]},"as":"objects"},{"from":"objects","analytic":{"partition_by":[],"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"functions":{"previous":{"fn":"lag","expr":{"property":{"name":"score","value":{"field":"payload"}}}}}}},{"select":["id","previous"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","previous"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "analytic property arguments use input scope rather than SELECT aliases" {
  for
    text in [
      "SELECT other AS payload, LAG(payload.score) OVER (ORDER BY id) AS previous FROM objects",
      "FROM objects AS t |> SELECT other AS payload, LAG(t.payload.score) OVER (ORDER BY id) AS previous",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      analytic_property_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      semantic(program).contains(
        "\"expr\":{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}}",
      ),
      msg="navigation reads the original receiver, not the projected other object",
    )
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("input-snapshot receiver must remain closed")
    }
  }
}

///|
test "analytic property arguments retain a Pipe range snapshot after SET" {
  let program = compile(
    @query.parse_query(
      "FROM objects AS original |> SET payload = other |> SELECT id, LAG(original.payload.score) OVER (ORDER BY id) AS previous, LEAD(payload.score, 0) OVER (ORDER BY id) AS current",
      syntax_limits(),
    ).unwrap(),
    analytic_property_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"value\":{\"field\":\"payload\"}"))
  assert_true(wire.contains("\"value\":{\"field\":\"aql_pipe_set_3\"}"))
  assert_eq(wire.split("\"analytic\":").length(), 2)
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("current and original receivers use ordinary checked slots")
  }
}

///|
test "analytic property arguments preserve the expression work limit" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT LAG(payload.score) OVER (ORDER BY id) AS previous FROM objects",
        syntax_limits(),
      ).unwrap(),
      analytic_property_context(),
      { ..construction_limits(), max_expression_work: 1, },
    )
    is Err(Expression({ issue: @expression.WorkLimit, .. })),
  )
}

///|
test "analytic property arguments lower computed values within the common call" {
  let program = compile(
    @query.parse_query(
      "SELECT id, LAG(payload.score + 1) OVER (ORDER BY id) AS previous FROM objects",
      syntax_limits(),
    ).unwrap(),
    analytic_property_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"fn\":\"lag\""))
  assert_true(wire.contains("\"property\""))
  assert_eq(wire.split("\"derive\":").length(), 1)
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ =>
      fail(
        "computed nullable values stay inside the common analytic expression",
      )
  }
}

///|
test "analytic property arguments preserve exact scope and frame refusals" {
  for
    text in [
      "SELECT LAG(missing.score) OVER (ORDER BY id) AS previous FROM objects", "FROM objects AS old |> AS current |> SELECT LAG(old.payload.score) OVER (ORDER BY id) AS previous",
      "SELECT other AS invented, LAG(invented.score) OVER (ORDER BY id) AS previous FROM objects",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        analytic_property_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=text,
    )
  }
  for
    text in [
      "SELECT FIRST_VALUE(payload.score) OVER (ORDER BY id) AS value FROM objects",
      "SELECT LAG(payload.score, -1) OVER (ORDER BY id) AS value FROM objects",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        analytic_property_context(),
        construction_limits(),
      )
      is Err(UnsupportedAnalytic),
      msg=text,
    )
  }
}

///|
test "analytic property member and receiver types are checked by the common owner" {
  for argument in ["payload.missing", "id.score"] {
    let program = compile(
      @query.parse_query(
        "SELECT LAG(" +
        argument +
        ") OVER (ORDER BY id) AS previous FROM objects",
        syntax_limits(),
      ).unwrap(),
      analytic_property_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Rejected(_),
      msg="Frontend must not fabricate a missing member or scalar object type",
    )
  }
}

///|
test "analytic property independent Program uses the ordinary checker" {
  match
    @check.check_parsed(
      analytic_property_expected(),
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("closed nullable object navigation needs no external inputs")
  }
}

///|
test "analytic property LAG matches an independent complete Program" {
  for
    text in [
      "SELECT id, LAG(payload.score) OVER (ORDER BY id) AS previous FROM objects",
      "FROM objects |> SELECT id, LAG(payload.score) OVER (ORDER BY id) AS previous",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      analytic_property_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(analytic_property_expected()))
  }
}

///|
test "analytic property navigation and frame calls retain common expressions" {
  for
    (function_name, window) in [
      ("LEAD", "ORDER BY id"),
      (
        "FIRST_VALUE", "ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW",
      ),
      (
        "LAST_VALUE", "ORDER BY id ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING",
      ),
    ] {
    let program = compile(
      @query.parse_query(
        "SELECT id, " +
        function_name +
        "(objects.`payload`.`score`) OVER (" +
        window +
        ") AS value FROM objects",
        syntax_limits(),
      ).unwrap(),
      analytic_property_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      semantic(program).contains(
        "\"expr\":{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}}",
      ),
    )
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("navigation/frame values use the checked property contract")
    }
  }
}

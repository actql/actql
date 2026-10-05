///|
fn analytic_order_expected() -> @program.Program {
  // Four input fields plus the reserved analytic output pos give suffix 5
  // under the existing private-slot allocator, independently of compilation.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","derive":{"aql_analytic_sort_5":{"negate":{"field":"amount"}}}},{"analytic":{"partition_by":[],"order_by":[{"field":"aql_analytic_sort_5","dir":"asc","nulls":"last"},{"field":"id","dir":"asc","nulls":"first"}],"functions":{"pos":{"fn":"row_number"}}}},{"select":["id","amount","pos"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","amount","pos"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "independent analytic expression order Program passes ordinary checker" {
  match
    @check.check_parsed(
      analytic_order_expected(),
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    NeedsInputs(_) => fail("The independent Values input is closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "SQL and Pipe OVER expression order lower to the independent Program" {
  for
    text in [
      "SELECT id, amount, ROW_NUMBER() OVER (ORDER BY -amount NULLS LAST, id) AS pos FROM orders ORDER BY id",
      "FROM orders |> SELECT id, amount, ROW_NUMBER() OVER (ORDER BY (-amount) NULLS LAST, (id)) AS pos |> ORDER BY id",
    ] {
    let actual = match
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      ) {
      Ok(actual) => actual
      Err(UnsupportedOrdering) =>
        fail("UnsupportedOrdering rejects an admitted OVER expression")
      Err(_) => fail("Unexpected Frontend rejection")
    }
    assert_eq(semantic(actual), semantic(analytic_order_expected()))
  }
}

///|
fn analytic_expression_program(text : String) -> @program.Program {
  compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
}

///|
test "OVER expressions use input slots rather than colliding SELECT aliases" {
  let program = analytic_expression_program(
    "SELECT -amount AS amount, ROW_NUMBER() OVER (ORDER BY amount + 1, id) AS pos FROM orders ORDER BY amount",
  )
  let wire = semantic(program)
  assert_true(
    wire.contains(
      "\"aql_analytic_sort_5\":{\"add\":[{\"field\":\"amount\"},{\"literal\":1}]}",
    ),
  )
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("Values and ordinary numeric expressions are closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "OVER order expressions share input evaluation across different windows" {
  let wire = semantic(
    analytic_expression_program(
      "SELECT ROW_NUMBER() OVER (ORDER BY amount + 1, id) AS pos, RANK() OVER (ORDER BY amount + 1 DESC) AS ranking FROM orders",
    ),
  )
  assert_eq(wire.split("\"add\":").length(), 2)
  assert_eq(wire.split("\"derive\":").length(), 2)
  assert_eq(wire.split("\"analytic\":").length(), 3)
  assert_eq(wire.split("\"field\":\"aql_analytic_sort_6\"").length(), 3)
}

///|
test "parenthesized OVER columns reuse input and constants are values" {
  let direct = semantic(
    analytic_expression_program(
      "SELECT id, ROW_NUMBER() OVER (ORDER BY ((id))) AS pos FROM orders",
    ),
  )
  assert_false(direct.contains("\"derive\":"))
  assert_true(direct.contains("\"field\":\"id\""))
  let constant = semantic(
    analytic_expression_program(
      "SELECT id, DENSE_RANK() OVER (ORDER BY 1) AS pos FROM orders",
    ),
  )
  assert_true(constant.contains("\"aql_analytic_sort_5\":{\"literal\":1}"))
  assert_true(constant.contains("\"field\":\"aql_analytic_sort_5\""))
}

///|
test "OVER retains old Pipe snapshot separately from the current column" {
  let wire = semantic(
    analytic_expression_program(
      "FROM orders AS before |> SET amount = -amount |> SELECT before.amount AS original, amount, ROW_NUMBER() OVER (ORDER BY before.amount + 1, id) AS pos",
    ),
  )
  assert_true(wire.contains("\"add\":[{\"field\":\"amount\"},{\"literal\":1}]"))
  assert_true(wire.contains("\"original\":\"amount\""))
  assert_true(wire.contains("\"amount\":\"aql_pipe_set_4\""))
}

///|
test "OVER refuses missing and sibling names without exposing computed slots" {
  for
    text in [
      "SELECT amount AS renamed, ROW_NUMBER() OVER (ORDER BY renamed) AS pos FROM orders",
      "SELECT ROW_NUMBER() OVER (ORDER BY pos) AS pos FROM orders", "FROM orders AS old |> AS current |> SELECT ROW_NUMBER() OVER (ORDER BY old.amount) AS pos",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=text,
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT ROW_NUMBER() OVER (ORDER BY missing + 1) AS pos FROM orders",
        syntax_limits(),
      ).unwrap(),
      values_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: UnknownReference, origin: Some(_), })),
  )
}

///|
test "OVER derived ordering keeps the common expression work budget" {
  let limits = { ..construction_limits(), max_expression_work: 1, }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT ROW_NUMBER() OVER (ORDER BY amount + 1) AS pos FROM orders",
        syntax_limits(),
      ).unwrap(),
      values_context(),
      limits,
    )
    is Err(Expression({ issue: WorkLimit, origin: None, })),
  )
}

///|
test "OVER property order retains nullable input receiver before SELECT alias" {
  let program = compile(
    @query.parse_query(
      "SELECT id, payload.score AS original_score, other AS payload, ROW_NUMBER() OVER (ORDER BY objects.payload.score + 1 NULLS LAST, id) AS pos FROM objects ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    order_property_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(program).contains(
      "\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}",
    ),
  )
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) =>
      fail("nullable properties use ordinary closed Values checking")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

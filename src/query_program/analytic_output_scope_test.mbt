///|
fn analytic_shadow_expected() -> @program.Program {
  // The rank is independent of the input amount. Four visible input fields
  // reserve suffix 4; projection restores the authored alias afterwards.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","analytic":{"partition_by":[],"order_by":[{"field":"amount","dir":"desc","nulls":"last"},{"field":"id","dir":"asc","nulls":"first"}],"functions":{"aql_analytic_output_4":{"fn":"row_number"}}}},{"select":["id",{"amount":"aql_analytic_output_4"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","amount"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "analytic alias collision lowers to an independent checked Program" {
  let expected = analytic_shadow_expected()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    text in [
      "SELECT id, ROW_NUMBER() OVER (ORDER BY amount DESC, id) AS amount FROM orders",
      "FROM orders |> SELECT id, ROW_NUMBER() OVER (ORDER BY amount DESC, id) AS amount",
      "FROM orders |> AS original |> SELECT id, ROW_NUMBER() OVER (ORDER BY amount DESC, id) AS amount",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "SELECT star sees analytic input columns without duplicating the new output" {
  let actual = compile(
    @query.parse_query(
      "SELECT *, ROW_NUMBER() OVER (ORDER BY amount, id) AS pos FROM orders",
      syntax_limits(),
    ).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Checked(_),
  )
  let wire = semantic(actual)
  assert_true(
    wire.contains(
      "\"fields\":[\"id\",\"customer_id\",\"status\",\"amount\",\"pos\"]",
    ),
  )
}

///|
test "analytic output alias is not a sibling SELECT expression input" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT ROW_NUMBER() OVER (ORDER BY amount, id) AS pos, pos + 1 AS later FROM orders",
        syntax_limits(),
      ).unwrap(),
      values_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

///|
test "qualifying an analytic alias cannot recover a nonexistent input column" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT ROW_NUMBER() OVER (ORDER BY amount, id) AS pos FROM orders ORDER BY orders.pos",
        syntax_limits(),
      ).unwrap(),
      values_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

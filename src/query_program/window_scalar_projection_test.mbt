///|
fn window_scalar_projection_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","analytic":{"partition_by":[],"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"functions":{"aql_select_window_0":{"fn":"row_number"}}}},{"derive":{"aql_query_expr_1":{"add":[{"field":"aql_select_window_0"},{"literal":1}]}}},{"select":["id",{"pos":"aql_query_expr_1"}]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","pos"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "independent window operand Program passes the ordinary checker" {
  match
    @check.check_parsed(
      window_scalar_projection_expected(),
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent Values Program is closed")
  }
}

///|
test "SELECT window operand matches the independent complete Program" {
  let actual = compile(
    @query.parse_query(
      "SELECT id, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos FROM orders ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(window_scalar_projection_expected()))
}

///|
fn window_scalar_checked(text : String) -> String raise {
  let actual = match
    compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    ) {
    Ok(value) => value
    Err(UnsupportedGrouping) => fail("UnsupportedGrouping: " + text)
    Err(UnsupportedAnalytic) => fail("UnsupportedAnalytic: " + text)
    Err(Expression({ issue: @expression.UnknownReference, .. })) =>
      fail("UnknownReference: " + text)
    Err(_) => fail(text)
  }
  match
    @check.check_parsed(
      actual,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the Values window expression must be closed: " + text)
  }
  semantic(actual)
}

///|
test "window operands compose in Pipe, conditional, multiple-window and named scopes" {
  for
    text in [
      "FROM orders |> SELECT id, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos |> ORDER BY id",
      "SELECT id, COALESCE(LAG(amount) OVER (ORDER BY id), 0) + ROW_NUMBER() OVER (ORDER BY amount DESC, id) AS pos FROM orders ORDER BY id",
      "SELECT id, CASE WHEN ROW_NUMBER() OVER w > 1 THEN amount ELSE 0 END AS pos FROM orders WINDOW w AS (ORDER BY id) ORDER BY id",
      "SELECT id, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos FROM orders QUALIFY pos > 2 ORDER BY id",
      "SELECT customer_id, COUNT(*) AS total, ROW_NUMBER() OVER (ORDER BY customer_id) + SUM(amount) AS pos FROM orders GROUP BY customer_id ORDER BY customer_id",
    ] {
    ignore(window_scalar_checked(text))
  }
}

///|
test "window expression private bindings do not expose siblings or removed ranges" {
  for
    text in [
      "SELECT amount AS invented, LAG(invented) OVER (ORDER BY id) + 1 AS pos FROM orders",
      "FROM orders AS old |> AS current |> SELECT LAG(old.amount) OVER (ORDER BY id) + 1 AS pos",
      "FROM orders |> SELECT id |> SELECT LAG(amount) OVER (ORDER BY id) + 1 AS pos",
      "SELECT ROW_NUMBER() OVER (ORDER BY id) + aql_select_window_0 AS pos FROM orders",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=text,
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT id AS invented, ROW_NUMBER() OVER (ORDER BY invented) + 1 AS pos FROM orders",
        syntax_limits(),
      ).unwrap(),
      values_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
}

///|
test "window expression private names preserve authored columns and input aliases" {
  let actual = window_scalar_checked(
    "FROM orders |> EXTEND amount AS aql_select_window_0 |> SELECT aql_select_window_0, ROW_NUMBER() OVER (ORDER BY id) + aql_select_window_0 AS pos |> ORDER BY pos",
  )
  assert_true(
    actual.contains("\"aql_select_window_1\":{\"fn\":\"row_number\"}"),
  )
  assert_true(actual.contains("{\"field\":\"aql_select_window_0\"}"))
  let collision = window_scalar_checked(
    "SELECT id, LAG(amount) OVER (ORDER BY id) + amount AS amount FROM orders ORDER BY id",
  )
  assert_true(collision.contains("\"expr\":{\"field\":\"amount\"}"))
  assert_true(collision.contains("{\"field\":\"amount\"}"))
}

///|
test "window expression invalid ranking arguments retain the existing typed refusal" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT ROW_NUMBER(id) OVER (ORDER BY id) + 1 AS pos FROM orders",
        syntax_limits(),
      ).unwrap(),
      values_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.InvalidArguments, .. })),
  )
}

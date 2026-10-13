///|
fn pipe_extend_window_control() -> @program.Program {
  // Independent common Program: preserve the complete input and add one window value.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","analytic":{"partition_by":[],"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"functions":{"pos":{"fn":"row_number"}}}},{"sort":[{"field":"id","dir":"asc","nulls":"first"}]},{"select":["id","customer_id","status","amount","pos"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","customer_id","status","amount","pos"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "EXTEND window has an independently checked common control" {
  match
    @check.check_parsed(
      pipe_extend_window_control(),
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent window preserves the complete input")
  }
}

///|
test "Pipe EXTEND adds the evaluated window slot to the current row" {
  let actual = compile(
    @query.parse_query(
      "FROM orders |> EXTEND ROW_NUMBER() OVER (ORDER BY id) AS pos |> ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(pipe_extend_window_control()))
}

///|
test "Pipe EXTEND named window is local to that operator" {
  let actual = compile(
    @query.parse_query(
      "FROM orders |> EXTEND ROW_NUMBER() OVER w AS pos WINDOW w AS (ORDER BY id) |> ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(pipe_extend_window_control()))
}

///|
test "EXTEND window operands retain sibling input scope and ordinary continuations" {
  for
    text in [
      "FROM orders |> EXTEND ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos |> WHERE pos > 1 |> SELECT id, pos |> ORDER BY pos |> LIMIT 1",
      "FROM orders AS before |> SET amount = -amount |> EXTEND LAG(before.amount) OVER (ORDER BY id) AS original, LAG(amount) OVER (ORDER BY id) AS `current` |> SELECT id, original, current |> ORDER BY id",
      "FROM orders |> EXTEND ROW_NUMBER() OVER w AS pos WINDOW base AS (ORDER BY id), w AS (base) |> EXTEND RANK() OVER w AS ranking WINDOW w AS (ORDER BY amount DESC, id) |> SELECT id, pos, ranking |> ORDER BY id",
      "FROM orders |> EXTEND amount AS aql_select_window_0 |> EXTEND ROW_NUMBER() OVER (ORDER BY id) + aql_select_window_0 AS pos |> SELECT id, pos |> ORDER BY id",
      "FROM orders |> AGGREGATE SUM(amount) AS total GROUP BY customer_id |> EXTEND LAG(total) OVER (ORDER BY customer_id) AS previous |> SELECT customer_id, total, previous |> ORDER BY customer_id",
    ] {
    assert_true(@query.parse_query(text, syntax_limits()) is Ok(_), msg=text)
    ignore(window_scalar_checked(text))
  }
}

///|
test "EXTEND sibling values never become window input aliases" {
  for
    text in [
      "FROM orders |> EXTEND amount AS invented, LAG(invented) OVER (ORDER BY id) AS pos",
      "FROM orders |> EXTEND ROW_NUMBER() OVER (ORDER BY id) AS pos, pos + 1 AS next",
      "FROM orders |> SELECT id |> EXTEND LAG(amount) OVER (ORDER BY id) AS pos",
      "FROM orders AS old |> AS `current` |> EXTEND LAG(old.amount) OVER (ORDER BY id) AS pos",
      "FROM orders |> EXTEND ROW_NUMBER() OVER (ORDER BY id) + aql_select_window_0 AS pos",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    assert_true(
      compile(query, values_context(), construction_limits())
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=text,
    )
  }
}

///|
test "EXTEND window names collide only in their local operator scope" {
  for
    text in [
      "FROM orders |> EXTEND ROW_NUMBER() OVER (ORDER BY id) AS id", "FROM orders |> EXTEND ROW_NUMBER() OVER (ORDER BY id) AS pos, RANK() OVER (ORDER BY id) AS pos",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    assert_true(
      compile(query, values_context(), construction_limits())
      is Err(DuplicateOutput),
      msg=text,
    )
  }
  for
    text in [
      "FROM orders |> EXTEND ROW_NUMBER() OVER w AS pos WINDOW w AS (ORDER BY id) |> EXTEND RANK() OVER w AS ranking",
      "FROM orders |> EXTEND ROW_NUMBER() OVER w AS pos WINDOW w AS (later), later AS (ORDER BY id)",
      "FROM orders |> EXTEND ROW_NUMBER() OVER w AS pos WINDOW w AS (ORDER BY id), W AS (ORDER BY amount)",
      "FROM orders |> EXTEND SUM(amount) AS total", "FROM orders |> EXTEND *",
    ] {
    assert_true(@query.parse_query(text, syntax_limits()) is Err(_), msg=text)
  }
}

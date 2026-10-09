///|
fn pipe_where_window_control() -> @program.Program {
  // Independent analytic -> filter -> sort -> public-current-row projection.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","analytic":{"partition_by":[],"order_by":[{"field":"y","dir":"asc","nulls":"first"}],"functions":{"aql_pipe_where_window_0":{"fn":"row_number"}}}},{"filter":{"lte":[{"field":"aql_pipe_where_window_0"},{"literal":1}]}},{"sort":[{"field":"x","dir":"asc","nulls":"first"}]},{"select":["x","y"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","y"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Pipe WHERE window independent control is accepted by the common checker" {
  match
    @check.check_parsed(
      pipe_where_window_control(),
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent Values control is closed")
  }
}

///|
test "Pipe WHERE window preserves the complete current row" {
  let actual = compile(
    @query.parse_query(
      "FROM t |> WHERE ROW_NUMBER() OVER (ORDER BY y) <= 1 |> ORDER BY x",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(pipe_where_window_control()))
}

///|
test "Pipe WHERE window uses its input scope before a subsequent projection" {
  ignore(
    window_scalar_checked(
      "FROM orders |> WHERE ROW_NUMBER() OVER (ORDER BY id) <= 1 |> SELECT id, amount |> ORDER BY id",
    ),
  )
}

///|
test "Pipe WHERE windows preserve current grouped projected and immutable input scopes" {
  for
    source in [
      "FROM orders |> WHERE ROW_NUMBER() OVER (ORDER BY id) <= 2 AND LAG(amount) OVER (ORDER BY id) > 0 |> SELECT id, amount |> ORDER BY id |> LIMIT 1",
      "FROM orders AS before |> SET amount = -amount |> WHERE LAG(before.amount) OVER (ORDER BY id) > 0 |> SELECT id, amount |> ORDER BY id",
      "FROM orders |> AGGREGATE SUM(amount) AS total GROUP BY customer_id |> WHERE ROW_NUMBER() OVER (ORDER BY total DESC, customer_id) = 1 |> SELECT customer_id, total |> ORDER BY customer_id",
      "SELECT customer_id, SUM(amount) AS total FROM orders GROUP BY customer_id |> WHERE ROW_NUMBER() OVER (ORDER BY total DESC, customer_id) = 1 |> SELECT customer_id, total |> ORDER BY customer_id",
      "FROM orders |> EXTEND amount AS aql_pipe_where_window_0 |> WHERE ROW_NUMBER() OVER (ORDER BY id) <= 1 |> SELECT id, aql_pipe_where_window_0 |> ORDER BY id",
      "FROM orders |> WHERE ROW_NUMBER() OVER (ORDER BY id) <= 2 |> WHERE ROW_NUMBER() OVER (ORDER BY id DESC) = 1 |> SELECT id |> ORDER BY id",
      "FROM orders |> WHERE COUNT(*) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) = 1 |> SELECT id |> ORDER BY id",
    ] {
    ignore(window_scalar_checked(source))
  }
}

///|
test "Pipe WHERE window placeholders cannot revive hidden fields or removed ranges" {
  for
    (source, reason) in [
      (
        "FROM orders |> WHERE LAG(missing) OVER (ORDER BY id) > 0", "UnknownReference",
      ),
      (
        "FROM orders |> SELECT id |> WHERE LAG(amount) OVER (ORDER BY id) > 0", "UnknownReference",
      ),
      (
        "FROM orders AS old |> AS current |> WHERE LAG(old.amount) OVER (ORDER BY id) > 0",
        "UnknownReference",
      ),
      (
        "FROM orders |> WHERE ROW_NUMBER() OVER (ORDER BY id) = 1 |> SELECT aql_pipe_where_window_0",
        "UnknownReference",
      ),
      (
        "FROM orders |> WHERE ROW_NUMBER() OVER (ORDER BY id) = 1 |> WHERE aql_pipe_where_window_0 > 0",
        "UnknownReference",
      ),
      (
        "FROM orders |> WHERE ROW_NUMBER() OVER (ORDER BY id) = 1 |> ORDER BY aql_pipe_where_window_0",
        "UnknownReference",
      ),
      (
        "FROM orders |> WHERE ROW_NUMBER() OVER (ORDER BY id) = 1 |> WHERE ROW_NUMBER() OVER (ORDER BY aql_pipe_where_window_0) = 1",
        "UnknownColumn",
      ),
    ] {
    let result = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    )
    let actual = match result {
      Err(Expression({ issue: @expression.UnknownReference, .. })) =>
        "UnknownReference"
      Err(UnknownColumn) => "UnknownColumn"
      Err(UnsupportedOrdering) => "UnsupportedOrdering"
      _ => fail("unexpected acceptance or refusal: " + source)
    }
    assert_eq(actual, reason)
  }
}

///|
test "Pipe WHERE keeps ordinary aggregation and window declarations out of its scope" {
  for
    (source, reason) in [
      (
        "FROM orders |> WHERE SUM(amount) > 0", "Pipe WHERE cannot introduce ordinary aggregation",
      ),
      (
        "FROM orders |> WHERE LAG(COUNT(*)) OVER (ORDER BY id) > 0", "Pipe WHERE cannot introduce ordinary aggregation",
      ),
      (
        "FROM orders |> SELECT id, ROW_NUMBER() OVER w AS n WINDOW w AS (ORDER BY id) |> WHERE ROW_NUMBER() OVER w = 1",
        "Unknown named window",
      ),
    ] {
    assert_true(
      @query.parse_query(source, syntax_limits())
      is Err({ issue: @query.Syntax(message), .. }) &&
      message == reason,
      msg=source,
    )
  }
  assert_true(
    @query.parse_query(
      "SELECT id FROM orders WHERE ROW_NUMBER() OVER (ORDER BY id) = 1",
      syntax_limits(),
    )
    is Err(_),
  )
}

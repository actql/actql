///|
fn pipe_set_window_control() -> @program.Program {
  // Independent common analytic -> derive -> sort -> current-column projection.
  // The existing physical-slot allocator starts at the three retained fields
  // (x, y, window value), so the new assignment slot is aql_pipe_set_3.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","analytic":{"partition_by":[],"order_by":[{"field":"y","dir":"asc","nulls":"first"}],"functions":{"aql_pipe_set_window_0":{"fn":"row_number"}}}},{"derive":{"aql_pipe_set_3":{"field":"aql_pipe_set_window_0"}}},{"sort":[{"field":"aql_pipe_set_3","dir":"asc","nulls":"first"}]},{"select":[{"x":"aql_pipe_set_3"},"y"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","y"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Pipe SET window has an independently checked ordinary Program" {
  match
    @check.check_parsed(
      pipe_set_window_control(),
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent SET window is closed")
  }
}

///|
test "Pipe SET reuses its window value for the current column" {
  let actual = compile(
    @query.parse_query(
      "FROM t |> SET x = ROW_NUMBER() OVER (ORDER BY y) |> ORDER BY x",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(pipe_set_window_control()))
}

///|
test "Pipe SET window scalar operands use the ordinary expression path" {
  ignore(
    window_scalar_checked(
      "FROM orders |> SET amount = ROW_NUMBER() OVER (ORDER BY id) + amount |> SELECT id, amount |> ORDER BY id",
    ),
  )
}

///|
test "Pipe SET window assignments share the immutable input snapshot" {
  for
    source in [
      "FROM orders |> SET amount = ROW_NUMBER() OVER (ORDER BY id), id = amount |> SELECT id, amount |> ORDER BY amount",
      "FROM orders AS before |> SET amount = ROW_NUMBER() OVER (ORDER BY id) |> SELECT id, before.amount AS original, amount |> ORDER BY id",
      "FROM orders |> SET amount = -amount |> SET amount = LAG(amount) OVER (ORDER BY id) |> SELECT id, amount |> ORDER BY id",
      "FROM orders |> AGGREGATE SUM(amount) AS total GROUP BY customer_id |> SET total = LAG(total) OVER (ORDER BY customer_id) |> SELECT customer_id, total |> ORDER BY customer_id",
      "SELECT customer_id, SUM(amount) AS total FROM orders GROUP BY customer_id |> SET total = ROW_NUMBER() OVER (ORDER BY total DESC, customer_id) |> ORDER BY customer_id",
      "FROM orders |> EXTEND amount AS aql_pipe_set_window_0 |> SET amount = ROW_NUMBER() OVER (ORDER BY id) + aql_pipe_set_window_0 |> SELECT id, amount |> ORDER BY id",
      "FROM orders |> SET amount = COUNT(*) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) |> WHERE amount > 0 |> SELECT id, amount |> ORDER BY id",
    ] {
    ignore(window_scalar_checked(source))
  }
}

///|
test "Pipe SET window targets retain existing column checks" {
  for
    source in [
      "FROM orders |> SET missing = ROW_NUMBER() OVER (ORDER BY id)", "FROM orders |> SET amount = ROW_NUMBER() OVER (ORDER BY id), amount = 1",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      )
      is Err(UnsupportedProjection),
      msg=source,
    )
  }
}

///|
test "Pipe SET window arguments cannot revive private slots or removed ranges" {
  for
    source in [
      "FROM orders |> SET amount = LAG(missing) OVER (ORDER BY id)", "FROM orders |> SELECT id |> SET id = LAG(amount) OVER (ORDER BY id)",
      "FROM orders AS old |> AS current |> SET amount = LAG(old.amount) OVER (ORDER BY id)",
      "FROM orders |> SET amount = ROW_NUMBER() OVER (ORDER BY id) + aql_pipe_set_window_0",
      "FROM orders |> SET amount = ROW_NUMBER() OVER (ORDER BY id) |> SELECT aql_pipe_set_window_0",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=source,
    )
  }
}

///|
test "Pipe SET windows introduce neither ordinary aggregation nor leaked WINDOW declarations" {
  for
    (source, reason) in [
      (
        "FROM orders |> SET amount = SUM(amount)", "Pipe SET cannot introduce ordinary aggregation",
      ),
      (
        "FROM orders |> SET amount = LAG(COUNT(*)) OVER (ORDER BY id)", "Pipe SET cannot introduce ordinary aggregation",
      ),
      (
        "FROM orders |> SELECT id, ROW_NUMBER() OVER w AS n WINDOW w AS (ORDER BY id) |> SET id = ROW_NUMBER() OVER w",
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
}

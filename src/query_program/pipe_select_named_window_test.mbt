///|
fn pipe_select_named_window_control() -> @program.Program {
  // Authored from the common analytic contract, independently of query output.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","analytic":{"partition_by":[],"order_by":[{"field":"y","dir":"asc","nulls":"first"}],"functions":{"n":{"fn":"row_number"}}}},{"select":["x","n"]},{"sort":[{"field":"x","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Pipe SELECT independent window control and existing inline source agree" {
  let expected = pipe_select_named_window_control()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent Values input is closed")
  }
  let actual = compile(
    @query.parse_query(
      "FROM t |> SELECT x, ROW_NUMBER() OVER (ORDER BY y) AS n |> ORDER BY x",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "Pipe SELECT named window matches the independent complete Program" {
  for
    source in [
      "FROM t |> SELECT x, ROW_NUMBER() OVER w AS n WINDOW w AS (ORDER BY y) |> ORDER BY x",
      "FROM t |> SELECT x, ROW_NUMBER() OVER (`W`) AS n WINDOW base AS (), ordered AS (base ORDER BY y), `w` AS ordered |> ORDER BY x",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(pipe_select_named_window_control()))
  }
}

///|
test "Pipe SELECT named scalar window operands reuse the independent Program" {
  let actual = compile(
    @query.parse_query(
      "FROM orders |> SELECT id, ROW_NUMBER() OVER w + 1 AS pos WINDOW w AS (ORDER BY id) |> ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(window_scalar_projection_expected()))
}

///|
test "Pipe SELECT local windows preserve star scalar frame and immutable input scopes" {
  for
    source in [
      "FROM orders |> SELECT * REPLACE (ROW_NUMBER() OVER w AS amount) WINDOW w AS (ORDER BY id) |> ORDER BY id",
      "FROM orders |> SELECT id, COUNT(*) OVER framed AS n WINDOW ordered AS (ORDER BY id), framed AS (ordered ROWS BETWEEN CURRENT ROW AND CURRENT ROW) |> ORDER BY id",
      "FROM orders AS before |> SET amount = -amount |> SELECT id, LAG(before.amount) OVER w AS original, LAG(amount) OVER w AS `current` WINDOW w AS (ORDER BY id) |> ORDER BY id",
      "FROM orders |> SELECT id, ROW_NUMBER() OVER w AS pos WINDOW w AS (ORDER BY id) |> SELECT id, pos, RANK() OVER w AS reverse_pos WINDOW w AS (ORDER BY id DESC) |> ORDER BY id",
      "FROM orders |> SELECT id WINDOW ignored AS (ORDER BY SUM(amount)) |> ORDER BY id",
    ] {
    ignore(window_scalar_checked(source))
  }
}

///|
test "Pipe SELECT window arguments see input columns rather than sibling aliases" {
  for
    source in [
      "FROM orders |> SELECT amount AS invented, LAG(invented) OVER w AS pos WINDOW w AS (ORDER BY id)",
      "FROM orders AS old |> AS `current` |> SELECT LAG(old.amount) OVER w AS pos WINDOW w AS (ORDER BY id)",
      "FROM orders |> SELECT id |> SELECT LAG(amount) OVER w AS pos WINDOW w AS (ORDER BY id)",
      "FROM orders |> SELECT ROW_NUMBER() OVER w + aql_select_window_0 AS pos WINDOW w AS (ORDER BY id)",
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
  assert_true(
    compile(
      @query.parse_query(
        "FROM orders |> SELECT id AS invented, ROW_NUMBER() OVER w AS pos WINDOW w AS (ORDER BY invented)",
        syntax_limits(),
      ).unwrap(),
      values_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
}

///|
test "Pipe SELECT local WINDOW checks retain exact conflict diagnostics" {
  for
    (source, reason) in [
      (
        "FROM orders |> SELECT ROW_NUMBER() OVER w AS n WINDOW w AS (ORDER BY id) |> SELECT ROW_NUMBER() OVER w AS next",
        "Unknown named window",
      ),
      (
        "FROM orders |> SELECT ROW_NUMBER() OVER w AS n WINDOW w AS later, later AS (ORDER BY id)",
        "Unknown named window",
      ),
      (
        "FROM orders |> SELECT ROW_NUMBER() OVER w AS n WINDOW w AS w", "Unknown named window",
      ),
      (
        "FROM orders |> SELECT ROW_NUMBER() OVER w AS n WINDOW w AS (ORDER BY id), `W` AS (ORDER BY amount)",
        "Duplicate named window",
      ),
      (
        "FROM orders |> SELECT ROW_NUMBER() OVER (w ORDER BY amount) AS n WINDOW w AS (ORDER BY id)",
        "Duplicate named window ORDER BY",
      ),
      (
        "FROM orders |> SELECT ROW_NUMBER() OVER (w PARTITION BY id) AS n WINDOW w AS (ORDER BY id)",
        "Named window cannot be combined with PARTITION BY",
      ),
      (
        "FROM orders |> SELECT ROW_NUMBER() OVER w AS n WINDOW w AS (ORDER BY SUM(amount))",
        "Pipe SELECT cannot introduce ordinary aggregation",
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

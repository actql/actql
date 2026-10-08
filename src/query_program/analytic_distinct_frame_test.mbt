///|
// Independent refusal from the selected GoogleSQL analytic resolver: authored
// DISTINCT cannot be combined with window ORDER BY or a window frame.
test "DISTINCT aggregate windows never reinterpret an authored ROWS frame" {
  for name in ["COUNT", "SUM", "AVG"] {
    let text = "SELECT " +
      name +
      "(DISTINCT amount) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS n FROM orders"
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      )
      is Err(UnsupportedAnalytic),
      msg=text,
    )
  }
}

///|
test "DISTINCT analytic refusal covers inherited and expression windows" {
  for
    text in [
      "SELECT COUNT(DISTINCT amount) OVER (w ROWS CURRENT ROW) AS n FROM orders WINDOW w AS (ORDER BY id)",
      "SELECT COUNT(DISTINCT amount) OVER w AS n FROM orders WINDOW w AS (ORDER BY id ROWS CURRENT ROW)",
      "SELECT id FROM orders QUALIFY SUM(DISTINCT amount) OVER (ORDER BY id ROWS CURRENT ROW) > 0",
      "SELECT id FROM orders ORDER BY AVG(DISTINCT amount) OVER (ORDER BY id ROWS CURRENT ROW)",
      "SELECT COALESCE(SUM(DISTINCT amount) OVER (ORDER BY id ROWS CURRENT ROW), 0) AS n FROM orders",
      "FROM orders |> SELECT AVG(DISTINCT amount) OVER (ORDER BY id ROWS CURRENT ROW) AS n",
      "SELECT COUNT(DISTINCT amount) OVER (ROWS CURRENT ROW) AS n FROM orders", "SELECT COUNT(DISTINCT amount) OVER () AS n FROM orders",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      )
      is Err(UnsupportedAnalytic),
      msg=text,
    )
  }
}

///|
test "ordinary analytic calls preserve an independent full Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","analytic":{"partition_by":[],"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"functions":{"n":{"fn":"count","field":"amount"},"total":{"fn":"sum","field":"amount"},"average":{"fn":"avg","field":"amount"}},"frame":{"start":"unbounded_preceding","end":"current_row"}}},{"select":["id","n","total","average"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","n","total","average"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  check_statistical_program(expected)
  let frame = "OVER (ORDER BY id ROWS UNBOUNDED PRECEDING)"
  let projection = "id, COUNT(amount) " +
    frame +
    " AS n, SUM(amount) " +
    frame +
    " AS total, AVG(amount) " +
    frame +
    " AS average"
  for
    text in [
      "SELECT " + projection + " FROM orders ORDER BY id",
      "FROM orders |> SELECT " + projection + " |> ORDER BY id",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    check_statistical_program(actual)
    assert_eq(semantic(actual), semantic(expected))
  }
  let grouped = compile(
    @query.parse_query(
      "SELECT COUNT(DISTINCT amount) AS n, SUM(DISTINCT amount) AS total, AVG(DISTINCT amount) AS average FROM orders",
      syntax_limits(),
    ).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  check_statistical_program(grouped)
  assert_eq(semantic(grouped).split("\"distinct\":true").length() - 1, 3)
}

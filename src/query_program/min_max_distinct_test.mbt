///|
test "grouped DISTINCT extrema match an independent checked Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","group":{"by":[],"aggregates":{"low":{"fn":"min","expr":{"add":[{"field":"amount"},{"literal":1}]}},"high":{"fn":"max","expr":{"add":[{"field":"amount"},{"literal":1}]}}}}},{"select":["low","high"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["low","high"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  check_statistical_program(expected)
  for
    text in [
      "SELECT MIN(DISTINCT amount + 1) AS low, MAX(DISTINCT amount + 1) AS high FROM orders",
      "FROM orders |> AGGREGATE MIN(DISTINCT amount + 1) AS low, MAX(DISTINCT amount + 1) AS high",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    check_statistical_program(actual)
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "grouped DISTINCT extrema preserve calls filters and input scopes" {
  for
    text in [
      "SELECT MIN(DISTINCT amount) AS n FROM orders", "SELECT `mIn`(DISTINCT amount) AS low, `MAX`(DISTINCT orders.amount) AS high FROM orders",
      "SELECT MIN(DISTINCT amount WHERE id = 'a') AS low, MAX(DISTINCT amount WHERE id = 'b') AS high FROM orders",
      "SELECT customer_id, MIN(DISTINCT amount) AS low FROM orders GROUP BY customer_id HAVING MAX(DISTINCT amount) > 0 ORDER BY MIN(DISTINCT amount)",
      "FROM orders |> AS t |> AGGREGATE MIN(DISTINCT t.amount) AS low, MAX(DISTINCT t.amount) AS high GROUP BY t.customer_id AS customer |> ORDER BY high DESC",
      "WITH chosen AS (SELECT amount FROM orders) SELECT MIN(DISTINCT amount) AS low FROM chosen",
      "SELECT COALESCE(MIN(DISTINCT amount), 0) AS low FROM orders WHERE FALSE",
    ] {
    check_statistical_program(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      ).unwrap(),
    )
  }
}

///|
test "grouped extrema normalization retains duplicate-sensitive aggregate modifiers" {
  let actual = compile(
    @query.parse_query(
      "SELECT MIN(DISTINCT amount) AS low, MAX(DISTINCT amount) AS high, SUM(DISTINCT amount) AS total, COUNT(DISTINCT amount) AS n FROM orders",
      syntax_limits(),
    ).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  check_statistical_program(actual)
  assert_eq(semantic(actual).split("\"distinct\":true").length() - 1, 2)
  assert_true(!semantic(actual).contains("\"distinct\":["))
}

///|
test "DISTINCT analytic extrema stay an explicit profile gap" {
  for name in ["MIN", "MAX"] {
    assert_true(
      compile(
        @query.parse_query(
          "SELECT " + name + "(DISTINCT amount) OVER () AS value FROM orders",
          syntax_limits(),
        ).unwrap(),
        values_context(),
        construction_limits(),
      )
      is Err(UnsupportedAnalytic),
    )
  }
}

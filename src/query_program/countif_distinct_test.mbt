///|
test "COUNTIF DISTINCT matches an independent common COUNT conditional Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","group":{"by":[],"aggregates":{"n":{"fn":"count","expr":{"if":[{"gt":[{"field":"amount"},{"literal":0}]},{"literal":true},{"literal":null}]},"distinct":true}}}},{"select":["n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  check_statistical_program(expected)
  for
    text in [
      "SELECT COUNTIF(DISTINCT amount > 0) AS n FROM orders", "FROM orders |> AGGREGATE COUNTIF(DISTINCT amount > 0) AS n",
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
test "COUNTIF DISTINCT preserves Boolean demand filters and input scopes" {
  for
    text in [
      "SELECT `CoUnTiF`(DISTINCT orders.amount > 0 WHERE orders.id = 'a') AS n FROM orders",
      "FROM orders |> AS before |> SET amount = 0 |> AGGREGATE COUNTIF(DISTINCT before.amount > 0) AS old_n, COUNTIF(amount > 0) AS current_n",
      "SELECT customer_id, COUNTIF(DISTINCT amount > 0) AS n FROM orders GROUP BY customer_id HAVING COUNTIF(DISTINCT amount > 1) > 0 ORDER BY n",
      "WITH chosen AS (SELECT amount FROM orders) SELECT COUNTIF(DISTINCT amount > 0) AS n FROM chosen",
      "SELECT COUNTIF(DISTINCT TRUE) AS n, COUNTIF(DISTINCT FALSE) AS zero, COUNTIF(DISTINCT NULL) AS none",
      "SELECT COUNTIF(DISTINCT 1 / 0 > 0 WHERE FALSE) AS n",
    ] {
    check_statistical_program(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      ).unwrap(),
    )
  }
  let rejected = compile(
    @query.parse_query(
      "SELECT COUNTIF(DISTINCT amount) AS n FROM orders",
      syntax_limits(),
    ).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(
      rejected,
      check_environment(numeric=true),
      None,
      check_limits(),
    )
    is Rejected(_),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT COUNTIF(DISTINCT missing > 0) AS n FROM orders",
        syntax_limits(),
      ).unwrap(),
      values_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

///|
test "COUNTIF DISTINCT keeps the authored predicate once in the Program" {
  let actual = compile(
    @query.parse_query(
      "SELECT COUNTIF(DISTINCT amount > 0) AS once, COUNTIF(amount > 0) AS every FROM orders",
      syntax_limits(),
    ).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  check_statistical_program(actual)
  assert_eq(semantic(actual).split("\"distinct\":true").length() - 1, 1)
  assert_eq(semantic(actual).split("\"gt\":[").length() - 1, 2)
  assert_true(semantic(actual).contains("\"fn\":\"count_if\""))
  assert_true(!semantic(actual).contains("\"distinct\":["))
}

///|
test "DISTINCT COUNTIF does not imply an authored analytic frame is supported" {
  for
    window in [
      "()", "(ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)",
    ] {
    assert_true(
      compile(
        @query.parse_query(
          "SELECT COUNTIF(DISTINCT amount > 0) OVER " +
          window +
          " AS n FROM orders",
          syntax_limits(),
        ).unwrap(),
        values_context(),
        construction_limits(),
      )
      is Err(UnsupportedAnalytic),
    )
  }
}

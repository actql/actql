///|
test "TRY_NUMBER literal SQL retains the independently authored Common Program" {
  for
    (argument, child) in [
      ("'12.5'", "{\"literal\":\"12.5\"}"),
      ("'not-a-number'", "{\"literal\":\"not-a-number\"}"),
      ("NULL", "{\"literal\":null}"),
    ] {
    let expected = google_scalar_literal_control(
      "{\"try_number\":{\"value\":" + child + "}}",
    )
    let actual = compile(
      @query.parse_query(
        "SELECT TRY_NUMBER(" + argument + ") AS value",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "TRY_NUMBER SQL and Pipe preserve the same original String field Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{"orders":{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"orders","derive":{"aql_query_expr_0":{"try_number":{"value":{"field":"status"}}}}},{"select":[{"value":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    source in [
      "SELECT TRY_NUMBER(status) AS value FROM orders", "FROM orders |> SELECT TRY_NUMBER(status) AS value",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      fixture_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=source)
  }
}

///|
test "SELECT ALL lowers to an independent ordinary Program without DISTINCT" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{"orders":{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"orders","filter":{"gt":[{"field":"amount"},{"literal":0}]}},{"select":["amount","id"]},{"sort":[{"field":"amount","dir":"asc","nulls":"first"},{"field":"id","dir":"asc","nulls":"first"}]},{"take":{"count":2,"offset":1},"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["amount","id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    text in [
      "SELECT ALL amount, id FROM orders WHERE amount > 0 ORDER BY amount, id LIMIT 2 OFFSET 1",
      "FROM orders |> WHERE amount > 0 |> SELECT ALL amount, id |> ORDER BY amount, id |> LIMIT 2 OFFSET 1",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      fixture_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(expected))
  }
}

///|
test "source-free SELECT ALL and query composition use the ordinary checker" {
  for
    text in [
      "SELECT ALL 1 AS id", "SELECT ALL 1 AS id |> SELECT ALL *", "WITH seed AS (SELECT ALL 1 AS id) SELECT ALL id FROM seed",
      "SELECT ALL id FROM (SELECT ALL 1 AS id) AS seed", "SELECT ALL 1 AS id UNION ALL SELECT ALL 1 AS id ORDER BY id",
      "SELECT ALL COUNT(*) AS n FROM orders", "FROM orders |> SELECT ALL id |> SELECT ALL id",
      "SELECT ALL 1 AS `ALL`", "FROM orders |> SELECT ALL id AS `ALL` |> SELECT ALL `ALL`",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("generated Values input should be closed: " + text)
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

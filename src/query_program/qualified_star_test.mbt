///|
test "qualified range star matches an independently authored checked projection" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","select":["id","amount"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","amount"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    text in [
      "SELECT o.* EXCEPT (customer_id, status) FROM orders AS o ORDER BY id", "FROM orders AS o |> SELECT o.* EXCEPT (customer_id, status) |> ORDER BY id",
      "SELECT `O`.* EXCEPT (customer_id, status) FROM orders AS o ORDER BY id",
    ] {
    let parsed = @query.parse_query(text, syntax_limits()).unwrap()
    let actual = compile(parsed, values_context(), construction_limits()).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("qualified star retains the ordinary checked Relation")
    }
  }
}

///|
test "range stars use current CTE JOIN and GROUP scopes" {
  for
    source in [
      "WITH chosen AS (SELECT x, y FROM t) SELECT c.* FROM chosen AS c ORDER BY x",
      "SELECT left_side.* FROM t AS left_side JOIN r ON left_side.x = r.k ORDER BY x",
      "SELECT right_side.*, t.x AS id FROM t LEFT JOIN r AS right_side ON t.x = right_side.k ORDER BY id",
      "SELECT o.* EXCEPT (y), COUNT(*) AS n FROM t AS o GROUP BY 1 ORDER BY x", "FROM t AS old |> SET y = -y |> SELECT old.* EXCEPT (x) |> ORDER BY y",
      "FROM t AS old |> AS current |> SELECT current.* EXCEPT (y) |> ORDER BY x",
    ] {
    let wire = checked_join_order(source)
    assert_true(wire.contains("\"results\":"), msg=source)
  }
}

///|
test "range stars never revive hidden renamed or projected aliases" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT q.* FROM t AS q JOIN r AS q ON x = k",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(AmbiguousRelation),
  )
  for
    source in [
      "SELECT missing.* FROM t", "SELECT t.* FROM t AS renamed", "FROM t AS old |> AS current |> SELECT old.*",
      "FROM t AS old |> SELECT x |> SELECT old.*",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=source,
    )
  }
  assert_true(
    compile(
      @query.parse_query("SELECT o.* FROM t AS o GROUP BY x", syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnsupportedGrouping),
  )
  assert_true(
    compile(
      @query.parse_query("SELECT o.payload.* FROM t AS o", syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnsupportedProjection),
  )
}

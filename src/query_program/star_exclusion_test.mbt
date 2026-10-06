///|
test "star exclusions match independent checked projection Programs" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","select":["id","amount"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","amount"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    text in [
      "SELECT * EXCEPT (customer_id, status) FROM orders ORDER BY id", "FROM orders |> SELECT * EXCEPT (`customer_id`, status) |> ORDER BY id",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("star exclusions use the ordinary checked projection")
    }
  }
}

///|
test "star exclusions retain current Pipe slots and grouped ordinal positions" {
  for
    text in [
      "FROM t AS old |> SET y = -y |> SELECT * EXCEPT (x) |> ORDER BY y", "FROM t |> RENAME x AS renamed |> SELECT * EXCEPT (y) |> ORDER BY renamed",
      "FROM t |> DROP y |> SELECT * EXCEPT (x), 1 AS value", "SELECT * EXCEPT (y), COUNT(*) AS n FROM t GROUP BY 1 ORDER BY x",
      "WITH chosen AS (SELECT x, y FROM t) SELECT * EXCEPT (y) FROM chosen ORDER BY x",
    ] {
    let wire = checked_join_order(text)
    assert_true(wire.contains("\"results\":"), msg=text)
  }
  let grouped = checked_join_order(
    "SELECT * EXCEPT (y), COUNT(*) AS n FROM t GROUP BY 1 ORDER BY x",
  )
  assert_true(grouped.contains("\"by\":[\"x\"]"))
  assert_true(grouped.contains("\"fields\":[\"x\",\"n\"]"))
}

///|
test "star exclusions reject unknown current names and ungrouped retained columns" {
  for
    text in [
      "SELECT * EXCEPT (missing) FROM t", "FROM t |> DROP y |> SELECT * EXCEPT (y)",
      "FROM t |> RENAME x AS renamed |> SELECT * EXCEPT (x)",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=text,
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        "SELECT * EXCEPT (x) FROM t GROUP BY x",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnsupportedGrouping),
  )
}

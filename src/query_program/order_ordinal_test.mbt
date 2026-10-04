///|
test "ORDER ordinal selects the evaluated output column in SQL and Pipe" {
  for
    source in [
      "SELECT y, x FROM t ORDER BY 2 DESC, 1", "FROM t |> SELECT y, x |> ORDER BY 2 DESC, 1",
    ] {
    let body = checked_join_order(source)
    assert_true(
      body.contains(
        "\"sort\":[{\"dir\":\"desc\",\"field\":\"x\",\"nulls\":\"last\"},{\"dir\":\"asc\",\"field\":\"y\",\"nulls\":\"first\"}]",
      ),
      msg=source,
    )
    assert_false(body.contains("aql_query_sort_"))
    assert_false(body.contains("aql_pipe_sort_"))
  }
}

///|
test "ORDER ordinal is retained by set query lowering" {
  let program = compile(
    @query.parse_query(
      "SELECT a, b FROM left_rows UNION ALL SELECT c, d FROM right_rows ORDER BY 2 DESC, 1",
      syntax_limits(),
    ).unwrap(),
    set_context(),
    construction_limits(),
  ).unwrap()
  let body = semantic(program)
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("set ordinal uses the ordinary output contract")
  }
  assert_true(
    body.contains(
      "\"sort\":[{\"dir\":\"desc\",\"field\":\"b\",\"nulls\":\"last\"},{\"dir\":\"asc\",\"field\":\"a\",\"nulls\":\"first\"}]",
    ),
  )
}

///|
test "ORDER ordinal agrees with an independent complete Program" {
  let program = compile(
    @query.parse_query("SELECT y, x FROM t ORDER BY 2 DESC, 1", syntax_limits()).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","select":["y","x"]},{"sort":[{"field":"x","dir":"desc","nulls":"last"},{"field":"y","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["y","x"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
}

///|
test "ORDER ordinal uses current Pipe columns and computed slots once" {
  for
    source in [
      "SELECT x + 1 AS score, y FROM t ORDER BY (1), +2", "SELECT DISTINCT x + 1 AS score, y FROM t ORDER BY 1",
      "FROM t |> AS original |> SET x = -x |> DROP y |> ORDER BY 1", "SELECT COUNT(*) AS n, x FROM t GROUP BY x ORDER BY 1 DESC, 2",
      "SELECT t.x + 1 AS score, t.y FROM t JOIN r ON t.x = r.k ORDER BY 1", "WITH seed AS (SELECT x, y FROM t) SELECT l.x + 1 AS score, l.y FROM seed AS l JOIN seed AS r ON l.x = r.x ORDER BY 1",
      "SELECT * FROM t ORDER BY 2",
    ] {
    let body = checked_join_order(source)
    assert_false(body.contains("aql_query_sort_"), msg=source)
    assert_false(body.contains("aql_pipe_sort_"), msg=source)
    assert_false(body.contains("aql_join_sort_"), msg=source)
  }
  let body = checked_join_order("SELECT x + 1 AS score, y FROM t ORDER BY 1")
  assert_eq(body.split("\"add\":").length(), 2)
}

///|
test "ORDER ordinal rejects invalid positions and noninteger literals" {
  for
    suffix in [
      "0", "-1", "3", "1.0", "1e0", "'x'", "NULL", "TRUE", "99999999999999999999999999999999999999",
    ] {
    for
      source in [
        "SELECT y, x FROM t ORDER BY " + suffix,
        "FROM t |> SELECT y, x |> ORDER BY " + suffix,
        "SELECT t.x, t.y FROM t JOIN r ON t.x = r.k ORDER BY " + suffix,
        "SELECT a, b FROM left_rows UNION ALL SELECT c, d FROM right_rows ORDER BY " +
        suffix,
      ] {
      let context = if source.contains("left_rows") {
        set_context()
      } else {
        join_order_context()
      }
      assert_true(
        compile(
          @query.parse_query(source, syntax_limits()).unwrap(),
          context,
          construction_limits(),
        )
        is Err(UnsupportedOrdering),
        msg=source,
      )
    }
  }
}

///|
test "ORDER ordinal does not reinterpret an arithmetic expression" {
  let body = checked_join_order("SELECT y, x FROM t ORDER BY 1 + 0")
  assert_true(body.contains("\"add\":[{\"literal\":1},{\"literal\":0}]"))
}

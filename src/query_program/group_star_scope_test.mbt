///|
test "GROUP star retains the input column order before aggregation" {
  let program = compile(
    @query.parse_query("SELECT * FROM t GROUP BY y, x", syntax_limits()).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":["y","x"],"aggregates":{}}},{"select":["x","y"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","y"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
}

///|
test "GROUP star and an explicit aggregate do not duplicate its output" {
  let body = checked_join_order("SELECT *, COUNT(*) AS n FROM t GROUP BY x, y")
  assert_true(body.contains("\"fields\":[\"x\",\"y\",\"n\"]"))
  assert_true(body.contains("\"select\":[\"x\",\"y\",\"n\"]"))
}

///|
test "GROUP star cannot silently drop an ungrouped input column" {
  for
    source in [
      "SELECT * FROM t GROUP BY x", "SELECT *, COUNT(*) AS n FROM t GROUP BY x",
      "WITH chosen AS (SELECT x, y FROM t) SELECT * FROM chosen GROUP BY x", "SELECT *, COUNT(*) AS y FROM t GROUP BY x",
      "SELECT *, COUNT(*) AS n FROM t", "SELECT *, -y AS y FROM t GROUP BY x, y",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnsupportedGrouping),
      msg=source,
    )
  }
}

///|
test "GROUP star keeps SELECT list placement and CTE input order" {
  for
    source in [
      "SELECT COUNT(*) AS n, * FROM t GROUP BY y, x", "WITH chosen AS (SELECT x, y FROM t) SELECT COUNT(*) AS n, * FROM chosen GROUP BY y, x",
    ] {
    let wire = checked_join_order(source)
    assert_true(wire.contains("\"fields\":[\"n\",\"x\",\"y\"]"), msg=source)
  }
}

///|
test "GROUP star resolves scoped JOIN columns without exposing private slots" {
  let source = "WITH a AS (SELECT 1 AS x, 20 AS y), b AS (SELECT 1 AS k), c AS (SELECT 1 AS z) SELECT *, COUNT(*) AS n FROM a JOIN b ON a.x = b.k JOIN c ON b.k = c.z GROUP BY c.z, b.k, a.y, a.x"
  let program = compile_query_script(
    @query.parse_query_script(source, syntax_limits()).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(program).contains("\"fields\":[\"x\",\"y\",\"k\",\"z\",\"n\"]"),
  )
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("scoped grouped JOIN Values must be closed")
  }
  assert_true(
    compile_query_script(
      @query.parse_query_script(
        "WITH a AS (SELECT 1 AS x, 20 AS y), b AS (SELECT 1 AS k), c AS (SELECT 1 AS z) SELECT * FROM a JOIN b ON a.x = b.k JOIN c ON b.k = c.z GROUP BY c.z, b.k, a.x",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnsupportedGrouping),
  )
}

///|
test "GROUP Pipe star uses the new AGGREGATE scope" {
  let wire = checked_join_order(
    "FROM t AS before |> AGGREGATE COUNT(*) AS n GROUP BY y, x |> SELECT *",
  )
  assert_true(wire.contains("\"fields\":[\"y\",\"x\",\"n\"]"))
}

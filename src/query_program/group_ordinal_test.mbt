///|
test "GROUP ordinal lowers SELECT positions to the existing grouped columns" {
  let program = compile(
    @query.parse_query(
      "SELECT y, x, COUNT(*) AS n FROM t GROUP BY 2, 1",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":["x","y"],"aggregates":{"n":{"fn":"count"}}}},{"select":["y","x","n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["y","x","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("group ordinal Values must be closed")
  }
}

///|
test "GROUP ordinal counts expanded input star columns in SELECT order" {
  let wire = checked_join_order("SELECT *, COUNT(*) AS n FROM t GROUP BY 2, 1")
  assert_true(wire.contains("\"by\":[\"y\",\"x\"]"))
  assert_true(wire.contains("\"fields\":[\"x\",\"y\",\"n\"]"))
}

///|
test "GROUP ordinal is forbidden in the Pipe AGGREGATE scope" {
  assert_true(
    compile(
      @query.parse_query(
        "FROM t |> AGGREGATE COUNT(*) AS n GROUP BY 1",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnsupportedGrouping),
  )
}

///|
test "GROUP ordinal uses selected input expressions instead of alias lookup" {
  let wire = checked_join_order(
    "SELECT -x AS x, -x AS other, COUNT(*) AS n FROM t GROUP BY (1) ORDER BY x",
  )
  assert_eq(wire.split("\"negate\":").length(), 2)
  assert_true(wire.contains("\"fields\":[\"x\",\"other\",\"n\"]"))
  let mixed = checked_join_order(
    "SELECT y AS x, x AS y, COUNT(*) AS n FROM t GROUP BY (+1), 2",
  )
  assert_true(mixed.contains("\"by\":[\"y\",\"x\"]"))
}

///|
test "GROUP ordinal star references cannot masquerade as SELECT literals" {
  let wire = checked_join_order("SELECT *, 1 AS one FROM t GROUP BY 2, 1")
  assert_true(
    wire.contains("\"derive\":{\"aql_query_expr_2\":{\"literal\":1}}"),
  )
  assert_true(wire.contains("\"fields\":[\"x\",\"y\",\"one\"]"))
}

///|
test "GROUP ordinal rejects invalid positions and aggregate or analytic values" {
  for
    source in [
      "SELECT x, y FROM t GROUP BY 0", "SELECT x, y FROM t GROUP BY -1", "SELECT x, y FROM t GROUP BY 3",
      "SELECT x, y FROM t GROUP BY 1.0", "SELECT x, y FROM t GROUP BY 1e0", "SELECT x, y FROM t GROUP BY '1'",
      "SELECT x, y FROM t GROUP BY TRUE", "SELECT x, y FROM t GROUP BY NULL", "SELECT x, y FROM t GROUP BY 999999999999999999999999999999999999",
      "SELECT x, COUNT(*) AS n FROM t GROUP BY 2", "SELECT COUNT(*) AS n, * FROM t GROUP BY 1",
      "SELECT ROW_NUMBER() OVER (ORDER BY x) AS rn, x FROM t GROUP BY 1", "FROM t |> AGGREGATE COUNT(*) AS n GROUP BY (1)",
      "FROM t |> AGGREGATE COUNT(*) AS n GROUP BY +1", "FROM t |> AGGREGATE COUNT(*) AS n GROUP BY '1'",
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
test "GROUP ordinal keeps ordinary arithmetic expressions as expressions" {
  let wire = checked_join_order("SELECT COUNT(*) AS n FROM t GROUP BY 1 + 0")
  assert_true(wire.contains("\"add\":[{\"literal\":1},{\"literal\":0}]"))
  assert_true(wire.contains("\"fields\":[\"n\"]"))
  assert_true(
    checked_join_order("SELECT 1 AS one FROM t GROUP BY 1").contains(
      "\"fields\":[\"one\"]",
    ),
  )
}

///|
test "GROUP ordinal works through CTE and scoped JOIN input slots" {
  let sources = [
    "WITH chosen AS (SELECT y, x FROM t) SELECT x, y, COUNT(*) AS n FROM chosen GROUP BY 2, 1",
    "WITH a AS (SELECT 1 AS x, 20 AS y), b AS (SELECT 1 AS k), c AS (SELECT 1 AS z) SELECT *, COUNT(*) AS n FROM a JOIN b ON a.x = b.k JOIN c ON b.k = c.z GROUP BY 4, 3, 2, 1 ORDER BY x",
  ]
  for source in sources {
    let program = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("grouped ordinal CTE/JOIN Values must be closed")
    }
  }
}

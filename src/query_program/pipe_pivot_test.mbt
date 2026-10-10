///|
fn pipe_pivot_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","pivot":{"index":["id","customer_id"],"column":"status","values":["open","closed"],"value":"amount","aggregate":"count"}},{"select":["id","customer_id",{"opened":"open"},"closed"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","customer_id","opened","closed"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Pipe PIVOT has an independent checked ordinary Program control" {
  let expected = pipe_pivot_expected()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent pivot is closed")
  }
}

///|
test "Pipe PIVOT connects aggregate arguments grouping columns and authored column order" {
  let query = @query.parse_query(
    "FROM orders |> PIVOT(COUNT(amount) FOR status IN ('open' AS opened, 'closed'))",
    syntax_limits(),
  ).unwrap()
  let actual = compile(query, values_context(), construction_limits()).unwrap()
  assert_eq(semantic(actual), semantic(pipe_pivot_expected()))
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the source pivot is closed")
  }
}

///|
test "Pipe PIVOT exposes a fresh range over renamed result columns" {
  for
    source in [
      "FROM orders AS old |> PIVOT(COUNT(old.amount) FOR old.status IN ('open' AS opened, 'closed')) AS current |> SELECT current.id,current.customer_id,current.opened,current.closed",
      "FROM orders |> PIVOT(COUNT(`AMOUNT`) FOR `STATUS` IN ('open' AS `opened`, 'closed')) reshaped |> SELECT reshaped.*",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(pipe_pivot_expected()))
  }
  for
    source in [
      "FROM orders AS old |> PIVOT(COUNT(amount) FOR status IN ('open')) |> SELECT old.id",
      "FROM orders |> PIVOT(COUNT(amount) FOR status IN ('open')) |> PIVOT(COUNT(amount) FOR status IN ('open'))",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      )
      is Err(_),
      msg=source,
    )
  }
}

///|
test "Pipe PIVOT uses current evaluated aggregate slots and retains untouched group fields" {
  let actual = compile(
    @query.parse_query(
      "FROM orders AS old |> SET amount = 99 |> RENAME status AS phase |> PIVOT(MIN(amount) AS m FOR phase IN ('open' AS present,'closed' AS absent)) |> ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(actual)
  assert_true(wire.contains("\"aggregate\":\"min\""))
  assert_true(wire.contains("\"value\":\"aql_pipe_set_4\""))
  assert_true(wire.contains("\"column\":\"status\""))
  assert_true(wire.contains("\"index\":[\"id\",\"customer_id\"]"))
  assert_true(
    wire.contains(
      "\"fields\":[\"id\",\"customer_id\",\"m_present\",\"m_absent\"]",
    ),
  )
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("current slots remain an ordinary checked pivot")
  }
}

///|
test "Pipe PIVOT does not fabricate names or ignore unknown references" {
  for
    source in [
      "FROM orders |> PIVOT(COUNT(missing) FOR status IN ('open'))", "FROM orders |> PIVOT(COUNT(amount) FOR unknown.status IN ('open'))",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=source,
    )
  }
  for
    source in [
      "FROM orders |> PIVOT(COUNT(amount) FOR status IN ('open' AS id))", "FROM orders |> PIVOT(COUNT(amount) FOR status IN ('open' AS X, 'closed' AS x))",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      )
      is Err(DuplicateOutput),
      msg=source,
    )
  }
}

///|
test "Pipe PIVOT consumes named UNION ALL output" {
  let named = "(SELECT 'kale' AS product, 51 AS sales, 'Q1' AS quarter UNION ALL SELECT 'kale' AS product, 51 AS sales, 'Q1' AS quarter UNION ALL SELECT 'kale' AS product, CAST(NULL AS FLOAT64) AS sales, 'Q2' AS quarter) |> PIVOT(COUNT(sales) FOR quarter IN ('Q2' AS second,'Q1' AS first)) AS shaped |> SELECT shaped.product, shaped.second, shaped.first"
  let actual = compile(
    @query.parse_query(named, syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    _ => fail("closed combined output must check without Source I/O")
  }
  assert_true(
    semantic(actual).contains("\"fields\":[\"product\",\"second\",\"first\"]"),
  )
}

///|
test "Pipe PIVOT accepts duplicate and NULL rows from a parenthesized UNION ALL" {
  let actual = compile(
    @query.parse_query(
      "(SELECT 'kale' AS product, 51 AS sales, 'Q1' AS quarter UNION ALL SELECT 'kale', 51, 'Q1' UNION ALL SELECT 'kale', CAST(NULL AS FLOAT64), 'Q2') |> PIVOT(COUNT(sales) FOR quarter IN ('Q2' AS second,'Q1' AS first))",
      syntax_limits(),
    ).unwrap(),
    values_context(),
    construction_limits(),
  ).unwrap()
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the duplicate/NULL source PIVOT is closed")
  }
}

///|
test "anonymous positional set fields do not supply public or BY NAME aliases" {
  for source in ["SELECT 1 AS id UNION ALL BY NAME SELECT 2", "SELECT 2"] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        values_context(),
        construction_limits(),
      )
      is Err(UnsupportedProjection),
      msg=source,
    )
  }
}

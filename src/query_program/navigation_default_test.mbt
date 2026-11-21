///|
test "SQL navigation default uses the checked constant and keeps the original offset" {
  let source = "FROM pair |> ASSERT UNIQUE BY (x) |> EXTEND LAG(y, 1, 0) OVER (ORDER BY x) AS earlier, LEAD(y, 2, 3) OVER (ORDER BY x) AS later |> SELECT earlier, later"
  let program = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  let terms = semantic(program)
  assert_true(terms.contains("\"default\":{\"literal\":0}"))
  assert_true(terms.contains("\"default\":{\"literal\":3}"))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("the authored test context fixes all inputs")
    Rejected(issue) => raise @check.diagnostic_cause(issue)
  }
}

///|
test "SQL navigation default refuses a row reference" {
  let source = "FROM pair |> ASSERT UNIQUE BY (x) |> EXTEND LAG(y, 1, x) OVER (ORDER BY x) AS earlier"
  match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ) {
    Err(Expression(_)) => ()
    _ => fail("a navigation default has no row scope")
  }
}

///|
test "original SQL three-argument LAG passes the common position check" {
  let source = "WITH t AS (SELECT 1 AS n, 'a' AS s, 10 AS v UNION ALL SELECT 2 AS n, 'b' AS s, 20 AS v UNION ALL SELECT 3 AS n, 'a' AS s, 30 AS v) SELECT LAG(v, 1, 0) OVER (ORDER BY n) AS x FROM t"
  let program = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("the original query has no external inputs")
    Rejected(issue) => raise @check.diagnostic_cause(issue)
  }
}

///|
test "navigation default has a compatible checked value domain" {
  let source = "FROM pair |> ASSERT UNIQUE BY (x) |> EXTEND LAG(y, 1, 'text') OVER (ORDER BY x) AS earlier"
  let program = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(program, check_environment(), None, check_limits())
    is Rejected(_),
  )
}

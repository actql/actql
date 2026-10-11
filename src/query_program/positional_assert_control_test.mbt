///|
test "positional ASSERT keeps the evaluated anonymous occurrence" {
  let source = "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-y |> ASSERT UNIQUE BY(kept) |> SELECT *) ORDER BY a,b"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("ASSERT lost positional projection: UnsupportedProjection")
    Err(DuplicateOutput) =>
      fail("ASSERT lost positional projection: DuplicateOutput")
    Err(_) => fail("unexpected positional ASSERT refusal")
  }
  match
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed positional ASSERT source")
  }
}

///|
test "positional ASSERT has an independently authored ordinary JSON control" {
  let program = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.positional_assert\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false},\"y\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":1,\"y\":10},{\"x\":2,\"y\":20}]},\"as\":\"input\"},{\"from\":\"input\",\"derive\":{\"neg\":{\"negate\":{\"field\":\"y\"}}}},{\"select\":[{\"kept\":\"x\"},\"neg\"]},{\"assert_rows\":{\"unique_by\":[\"kept\"]}},{\"select\":[{\"a\":\"kept\"},{\"b\":\"neg\"}],\"as\":\"right\"},{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false},\"b\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"a\":0,\"b\":0}]},\"as\":\"left\"},{\"from\":\"left\",\"append\":{\"with\":\"right\"}},{\"sort\":[{\"field\":\"a\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"b\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"ordered\"}],\"results\":{\"rows\":{\"from\":\"ordered\",\"fields\":[\"a\",\"b\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed independent ASSERT input")
  }
}

///|
test "positional ASSERT retains immutable range keys and separately evaluated values" {
  for
    source in [
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-y |> AS r |> ASSERT UNIQUE BY(r.kept) |> SELECT r.*) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-y |> AS r |> SET kept=7 |> ASSERT UNIQUE BY(r.kept) |> SELECT *) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS kept,y AS v,-y AS `V` |> ASSERT UNIQUE BY(kept) |> SELECT *) ORDER BY a,b,c",
      "SELECT 0 AS a,0 AS b WHERE FALSE UNION ALL (FROM t |> WHERE FALSE |> SELECT x AS kept,-y |> ASSERT UNIQUE BY(kept) |> SELECT *) ORDER BY a,b",
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("closed positional assertion boundary")
    }
  }
}

///|
test "positional ASSERT keys cannot read internal values, dropped inputs or ambiguous aliases" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-y |> ASSERT UNIQUE BY(aql_set_anonymous_4) |> SELECT *) ORDER BY a,b",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS v,-y AS `V` |> ASSERT UNIQUE BY(v) |> SELECT *) ORDER BY a,b",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(AmbiguousColumn),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS v,-y AS `V` |> AS r |> ASSERT UNIQUE BY(r.v) |> SELECT *) ORDER BY a,b",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(AmbiguousColumn),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-y |> ASSERT UNIQUE BY(x) |> SELECT *) ORDER BY a,b",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-y |> AS before |> AS current |> ASSERT UNIQUE BY(before.kept) |> SELECT *) ORDER BY a,b",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-y |> AS r |> ASSERT UNIQUE BY(r.aql_set_anonymous_4) |> SELECT *) ORDER BY a,b",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
}

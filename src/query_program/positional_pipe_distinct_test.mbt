///|
test "positional Pipe DISTINCT preserves the preceding anonymous projection" {
  let source = "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-y |> DISTINCT) ORDER BY a,b"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("DISTINCT lost positional projection: UnsupportedProjection")
    Err(_) => fail("unexpected positional DISTINCT source refusal")
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
    NeedsInputs(_) => fail("closed positional DISTINCT input")
  }
}

///|
test "positional Pipe DISTINCT preserves separately evaluated duplicate aliases" {
  let source = "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS v,-y AS `V` |> DISTINCT) ORDER BY a,b"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(DuplicateOutput) =>
      fail("DISTINCT lost positional projection: DuplicateOutput")
    Err(_) => fail("unexpected duplicate positional DISTINCT source refusal")
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
    NeedsInputs(_) => fail("closed duplicate DISTINCT input")
  }
}

///|
test "positional DISTINCT has an independently authored checked JSON control" {
  let program = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.positional_distinct\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false},\"y\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":1,\"y\":10},{\"x\":1,\"y\":20},{\"x\":1,\"y\":10}]},\"as\":\"input\"},{\"from\":\"input\",\"derive\":{\"neg\":{\"negate\":{\"field\":\"y\"}}}},{\"select\":[{\"kept\":\"x\"},\"neg\"]},{\"distinct\":[\"kept\",\"neg\"]},{\"select\":[{\"a\":\"kept\"},{\"b\":\"neg\"}],\"as\":\"right\"},{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false},\"b\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"a\":0,\"b\":0}]},\"as\":\"left\"},{\"from\":\"left\",\"append\":{\"with\":\"right\"}},{\"sort\":[{\"field\":\"a\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"b\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"ordered\"}],\"results\":{\"rows\":{\"from\":\"ordered\",\"fields\":[\"a\",\"b\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
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
    NeedsInputs(_) => fail("closed independent DISTINCT control")
  }
}

///|
test "positional DISTINCT retains anonymous values through current column edits" {
  for
    source in [
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-y |> AS r |> DISTINCT |> WHERE r.kept>0) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-y |> AS r |> SET kept=1 |> DISTINCT) ORDER BY a,b",
      "SELECT 0 AS a UNION ALL (FROM t |> SELECT x AS v,-x AS `V`,y+1 |> DISTINCT |> DROP v) ORDER BY a",
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-y |> DISTINCT |> RENAME kept AS renamed |> WHERE renamed>0) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-y |> DISTINCT |> WHERE kept>0 |> ORDER BY -kept,2 |> LIMIT 1 OFFSET 1) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b WHERE FALSE UNION ALL (FROM t |> SELECT x AS kept,CAST(NULL AS FLOAT64) |> DISTINCT) ORDER BY a,b NULLS LAST",
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
      NeedsInputs(_) => fail("closed positional DISTINCT edit")
    }
  }
}

///|
test "positional DISTINCT keeps private and ambiguous authored references inaccessible" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-y |> DISTINCT |> WHERE aql_set_anonymous_4>0) ORDER BY a,b",
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
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS v,-y AS `V` |> DISTINCT |> WHERE v>0) ORDER BY a,b",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(AmbiguousColumn),
  )
  for
    source in [
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-y |> DISTINCT |> WHERE y>0) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-y |> AS before |> AS `current` |> DISTINCT |> WHERE before.kept>0) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-y |> AS r |> SET kept=1 |> DISTINCT |> WHERE r.kept>0) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-y |> AS r |> DISTINCT |> WHERE r.aql_set_anonymous_4>0) ORDER BY a,b",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=source,
    )
  }
}

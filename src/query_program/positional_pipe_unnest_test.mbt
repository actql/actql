///|
test "positional UNNEST preserves anonymous projection" {
  let source = "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS kept,-y |> CROSS JOIN UNNEST([10,20]) AS element |> SELECT *) ORDER BY a,b,c"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("UNNEST lost positional projection: UnsupportedProjection")
    Err(_) => fail("unexpected positional UNNEST refusal")
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
    NeedsInputs(_) => fail("closed positional UNNEST input")
  }
}

///|
test "positional UNNEST preserves duplicate projection" {
  let source = "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS v,-y AS `V` |> CROSS JOIN UNNEST([10,20]) AS element |> SELECT *) ORDER BY a,b,c"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(DuplicateOutput) =>
      fail("UNNEST lost positional projection: DuplicateOutput")
    Err(_) => fail("unexpected positional UNNEST refusal")
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
    NeedsInputs(_) => fail("closed positional UNNEST input")
  }
}

///|
test "positional UNNEST independent JSON control uses the ordinary checker" {
  let program = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.positional_unnest\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false},\"y\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":1,\"y\":10},{\"x\":2,\"y\":20}]},\"as\":\"input\"},{\"from\":\"input\",\"derive\":{\"neg\":{\"negate\":{\"field\":\"y\"}}}},{\"select\":[{\"kept\":\"x\"},\"neg\"]},{\"derive\":{\"items\":{\"array\":[{\"literal\":10},{\"literal\":20}]}}},{\"unnest\":{\"column\":\"items\",\"as\":\"element\"}},{\"select\":[{\"a\":\"kept\"},{\"b\":\"neg\"},{\"c\":\"element\"}],\"as\":\"right\"},{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false},\"b\":{\"type\":\"number\",\"nullable\":false},\"c\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"a\":0,\"b\":0,\"c\":0}]},\"as\":\"left\"},{\"from\":\"left\",\"append\":{\"with\":\"right\"}},{\"sort\":[{\"field\":\"a\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"b\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"c\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"ordered\"}],\"results\":{\"rows\":{\"from\":\"ordered\",\"fields\":[\"a\",\"b\",\"c\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
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
    NeedsInputs(_) => fail("closed independent UNNEST input")
  }
}

///|
test "positional UNNEST keeps current values, offsets, predicates and authored private-shaped destinations" {
  for
    source in [
      "SELECT 0 AS a,0 AS b,0 AS c,0 AS d UNION ALL (FROM t |> SELECT x AS kept,-y |> CROSS JOIN UNNEST([kept,kept+1]) AS element WITH OFFSET position |> SELECT *) ORDER BY a,b,c,d",
      "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS kept,-y |> AS r |> SET kept=7 |> CROSS JOIN UNNEST([r.kept]) AS element |> SELECT *) ORDER BY a,b,c",
      "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS kept,-y |> INNER JOIN UNNEST([NULL,1,2]) AS element ON element=kept |> SELECT *) ORDER BY a,b,c",
      "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS kept,-y |> CROSS JOIN UNNEST([10]) AS aql_set_anonymous_4 |> WHERE aql_set_anonymous_4>0 |> SELECT *) ORDER BY a,b,c",
      "SELECT 0 AS a,0 AS b,0 AS c,0 AS d UNION ALL (FROM t |> SELECT x AS v,-y AS `V` |> CROSS JOIN UNNEST([10]) AS element WITH OFFSET aql_set_duplicate_2 |> SELECT *) ORDER BY a,b,c,d",
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
      NeedsInputs(_) => fail("closed positional UNNEST boundary")
    }
  }
}

///|
test "positional UNNEST arguments cannot read private or ambiguous projected values" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS kept,-y |> CROSS JOIN UNNEST([aql_set_anonymous_4]) AS element |> SELECT *) ORDER BY a,b,c",
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
        "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS v,-y AS `V` |> CROSS JOIN UNNEST([v]) AS element |> SELECT *) ORDER BY a,b,c",
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
        "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS v,-y AS `V` |> AS r |> CROSS JOIN UNNEST([r.v]) AS element |> SELECT *) ORDER BY a,b,c",
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
        "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS kept,-y |> CROSS JOIN UNNEST([y]) AS element |> SELECT *) ORDER BY a,b,c",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS kept,-y |> CROSS JOIN UNNEST([t.x]) AS element |> SELECT *) ORDER BY a,b,c",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

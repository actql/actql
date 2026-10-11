///|
test "PIVOT COUNT star counts NULL rows while retaining all unreferenced columns" {
  let source = "(SELECT CAST(NULL AS FLOAT64) AS n,'A' AS axis UNION ALL SELECT CAST(NULL AS FLOAT64),'A' UNION ALL SELECT 1,'A') |> PIVOT(COUNT(*) FOR axis IN('A')) |> ORDER BY n NULLS LAST"
  let query = match @query.parse_query(source, syntax_limits()) {
    Ok(query) => query
    Err({ issue: @query.Syntax(reason), .. }) =>
      fail("COUNT star syntax refusal: " + reason)
    Err(_) => fail("unexpected COUNT star parse failure")
  }
  let program = compile(
    query,
    { ..values_context(), inputs: [], },
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
    NeedsInputs(_) => fail("closed COUNT star source")
  }
}

///|
test "PIVOT row count is representable by an independent existing Program" {
  let program = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pivot_count_star\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":true},\"axis\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"n\":null,\"axis\":\"A\"},{\"n\":null,\"axis\":\"A\"},{\"n\":1,\"axis\":\"A\"}]},\"as\":\"rows\"},{\"from\":\"rows\",\"derive\":{\"row_witness\":{\"literal\":1}}},{\"pivot\":{\"index\":[\"n\"],\"column\":\"axis\",\"value\":\"row_witness\",\"values\":[\"A\"],\"aggregate\":\"count\"}},{\"sort\":[{\"field\":\"n\",\"dir\":\"asc\",\"nulls\":\"last\"}]},{\"select\":[\"n\",\"A\"],\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"n\",\"A\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
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
    NeedsInputs(_) => fail("closed independent row count")
  }
}

///|
test "PIVOT COUNT star retains nullable keys empty groups range axis and authored names" {
  for
    source in [
      "SELECT 'A' AS axis WHERE FALSE |> PIVOT(COUNT(*) FOR axis IN('B' AS later,'A' AS first))",
      "SELECT 1 AS n,'A' AS axis WHERE FALSE |> PIVOT(COUNT(*) FOR axis IN('A'))",
      "SELECT CAST(NULL AS FLOAT64) AS n,'A' AS axis |> AS old |> PIVOT(COUNT(*) AS total FOR old.axis IN('B','A')) AS current |> SELECT current.*",
      "SELECT 9 AS aql_pivot_row_4,'A' AS axis |> PIVOT(COUNT(*) FOR axis IN('A'))",
      "SELECT 'A' AS axis |> PIVOT(COUNT(*) FOR axis IN('A' AS aql_pivot_row_4))",
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      { ..values_context(), inputs: [], },
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
      NeedsInputs(_) => fail("closed COUNT star boundary")
    }
  }
}

///|
test "PIVOT COUNT star private row witness cannot become an authored expression receiver" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 'A' AS axis |> PIVOT(COUNT(*) FOR axis IN('A')) |> SELECT aql_pivot_row_4",
        syntax_limits(),
      ).unwrap(),
      { ..values_context(), inputs: [], },
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

///|
test "positional-extend-after-projection retains the prior ordinal values" {
  let program = match
    compile(
      @query.parse_query(
        "SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM t |> SELECT x AS kept, -x |> EXTEND kept + 10 AS extra) ORDER BY a, b, c",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail(
        "pure Pipe tail erased the prior positional projection: UnsupportedProjection",
      )
    Err(_) => fail("unexpected pure Pipe tail refusal")
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
    NeedsInputs(_) => fail("closed positional source control")
  }
}

///|
test "positional-as-after-projection retains the prior ordinal values" {
  let program = match
    compile(
      @query.parse_query(
        "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> AS r |> WHERE r.kept > 1) ORDER BY a, b",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail(
        "pure Pipe tail erased the prior positional projection: UnsupportedProjection",
      )
    Err(_) => fail("unexpected pure Pipe tail refusal")
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
    NeedsInputs(_) => fail("closed positional source control")
  }
}

///|
test "independently authored pure tail controls retain values and scope" {
  for
    source in [
      "{\"version\":\"actql/0.1\",\"id\":\"fixture.positional_extend\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":2},{\"x\":1}]},\"as\":\"input\"},{\"from\":\"input\",\"derive\":{\"neg\":{\"negate\":{\"field\":\"x\"}}}},{\"select\":[{\"kept\":\"x\"},\"neg\"]},{\"derive\":{\"extra\":{\"add\":[{\"field\":\"kept\"},{\"literal\":10}]}}},{\"select\":[{\"a\":\"kept\"},{\"b\":\"neg\"},{\"c\":\"extra\"}],\"as\":\"right\"},{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false},\"b\":{\"type\":\"number\",\"nullable\":false},\"c\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"a\":0,\"b\":0,\"c\":0}]},\"as\":\"left\"},{\"from\":\"left\",\"append\":{\"with\":\"right\"}},{\"sort\":[{\"field\":\"a\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"b\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"c\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"ordered\"}],\"results\":{\"rows\":{\"from\":\"ordered\",\"fields\":[\"a\",\"b\",\"c\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
      "{\"version\":\"actql/0.1\",\"id\":\"fixture.positional_as\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":2},{\"x\":1}]},\"as\":\"input\"},{\"from\":\"input\",\"derive\":{\"neg\":{\"negate\":{\"field\":\"x\"}}}},{\"select\":[{\"kept\":\"x\"},\"neg\"]},{\"filter\":{\"gt\":[{\"field\":\"kept\"},{\"literal\":1}]}},{\"select\":[{\"a\":\"kept\"},{\"b\":\"neg\"}],\"as\":\"right\"},{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false},\"b\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"a\":0,\"b\":0}]},\"as\":\"left\"},{\"from\":\"left\",\"append\":{\"with\":\"right\"}},{\"sort\":[{\"field\":\"a\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"b\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"ordered\"}],\"results\":{\"rows\":{\"from\":\"ordered\",\"fields\":[\"a\",\"b\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    ] {
    let program = @program.parse(
      source,
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
      NeedsInputs(_) => fail("closed independent JSON control")
    }
  }
}

///|
test "pure positional tails retain snapshots and private-shaped authored destinations" {
  for
    source in [
      "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS kept,-x |> EXTEND kept+10 AS aql_set_anonymous_4 |> WHERE aql_set_anonymous_4 > 11) ORDER BY a,b,c",
      "SELECT 0 AS a,0 AS b,0 AS c,0 AS d UNION ALL (FROM t |> SELECT x AS v,-x AS `V`,x+10 AS kept |> EXTEND kept+1 AS `AQL_SET_DUPLICATE_5` |> WHERE aql_set_duplicate_5 > 12) ORDER BY a,b,c,d",
      "SELECT 0 AS a,0 AS b,0 AS c,0 AS d UNION ALL (FROM t |> SELECT x AS v,-x AS `V`,x+10 AS kept |> EXTEND kept+1 AS `AQL_SET_DUPLICATE_5` |> AS r |> WHERE r.aql_set_duplicate_5 > 12) ORDER BY a,b,c,d",
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-x |> AS r |> SET kept=kept+10 |> WHERE r.kept > 1) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-x |> AS first |> AS second |> WHERE second.kept > 1) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS kept,-x |> EXTEND ROW_NUMBER() OVER (ORDER BY kept DESC) AS rank) ORDER BY a,b,c",
      "SELECT 0 AS a,0 AS b,0 AS c,0 AS d UNION ALL (FROM t |> SELECT x AS kept,-x |> EXTEND kept+1 AS first,kept+10 AS second) ORDER BY a,b,c,d",
      "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS kept,CAST(NULL AS FLOAT64) |> EXTEND kept+10 AS extra) ORDER BY a,b,c",
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS aql_set_anonymous_4,-x |> AS r |> WHERE r.aql_set_anonymous_4 > 1) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS kept,-x |> RENAME kept AS renamed |> EXTEND renamed+10 AS extra |> AS r |> WHERE r.renamed > 1) ORDER BY a,b,c",
    ] {
    let program = match
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(_) => fail("unexpected source refusal: " + source)
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
      NeedsInputs(_) => fail("closed pure tail boundary")
    }
  }
}

///|
test "EXTEND cannot read anonymous private or ambiguous authored values" {
  let head = "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS kept,-x |> EXTEND "
  for
    expression in [
      "aql_set_anonymous_4+1 AS extra", "`AQL_SET_ANONYMOUS_4`+1 AS extra",
    ] {
    assert_true(
      compile(
        @query.parse_query(
          head + expression + ") ORDER BY a,b,c",
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnknownColumn),
    )
  }
  let duplicate = "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS v,-x AS `V` |> EXTEND v+1 AS extra) ORDER BY a,b,c"
  assert_true(
    compile(
      @query.parse_query(duplicate, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(AmbiguousColumn),
  )
  assert_true(
    compile(
      @query.parse_query(
        head + "kept+1 AS kept) ORDER BY a,b,c",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(DuplicateOutput),
  )
}

///|
test "AS cannot qualify private fields while authored duplicate qualifiers remain ambiguous" {
  for
    source in [
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-x |> AS r |> WHERE r.aql_set_anonymous_4 > 0) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-x |> AS r |> WHERE r.`AQL_SET_ANONYMOUS_4` > 0) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS kept,-x |> EXTEND kept+10 AS aql_set_anonymous_4 |> AS r |> WHERE r.aql_set_anonymous_5 > 0) ORDER BY a,b,c",
      "SELECT 0 AS a,0 AS b,0 AS c,0 AS d UNION ALL (FROM t |> SELECT x AS v,-x AS `V`,x+10 AS kept |> EXTEND kept+1 AS aql_set_duplicate_5 |> AS r |> WHERE r.aql_set_duplicate_6 > 0) ORDER BY a,b,c,d",
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
  for tail in ["WHERE r.v > 0", "EXTEND r.v+1 AS extra |> DROP extra"] {
    let source = "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS v,-x AS `V` |> AS r |> " +
      tail +
      ") ORDER BY a,b"
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(AmbiguousColumn),
      msg=source,
    )
  }
}

///|
test "EXTEND siblings and AS receivers cannot restore dropped or displaced names" {
  for
    source in [
      "SELECT 0 AS a,0 AS b,0 AS c,0 AS d UNION ALL (FROM t |> SELECT x AS kept,-x |> EXTEND kept+1 AS first,first+1 AS second) ORDER BY a,b,c,d",
      "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS kept,-x |> EXTEND x+1 AS extra) ORDER BY a,b,c",
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-x |> AS r |> WHERE r.x > 0) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> AS old |> SELECT x AS kept,-x |> AS r |> WHERE old.x > 0) ORDER BY a,b",
      "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS kept,-x |> AS first |> AS second |> WHERE first.kept > 0) ORDER BY a,b",
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

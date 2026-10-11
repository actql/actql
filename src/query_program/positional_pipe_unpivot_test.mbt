///|
test "positional UNPIVOT retains the evaluated anonymous parent occurrence" {
  let source = "SELECT 0 AS a,0 AS b,'anchor' AS c UNION ALL (FROM t |> SELECT x AS kept,-y |> UNPIVOT INCLUDE NULLS(value FOR label IN(kept)) |> SELECT *) ORDER BY a,b,c"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("UNPIVOT lost positional projection: UnsupportedProjection")
    Err(_) => fail("unexpected positional UNPIVOT refusal")
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
    NeedsInputs(_) => fail("closed positional UNPIVOT input")
  }
}

///|
test "positional UNPIVOT has an independently authored ordinary JSON control" {
  let program = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.positional_unpivot\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false},\"y\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":1,\"y\":10},{\"x\":2,\"y\":20}]},\"as\":\"input\"},{\"from\":\"input\",\"derive\":{\"neg\":{\"negate\":{\"field\":\"y\"}}}},{\"select\":[{\"kept\":\"x\"},\"neg\"]},{\"unpivot\":{\"columns\":[\"kept\"],\"keep\":[\"neg\"],\"value_column\":\"value\",\"name_column\":\"label\"}},{\"select\":[{\"a\":\"neg\"},{\"b\":\"value\"},{\"c\":\"label\"}],\"as\":\"right\"},{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false},\"b\":{\"type\":\"number\",\"nullable\":false},\"c\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"a\":0,\"b\":0,\"c\":\"anchor\"}]},\"as\":\"left\"},{\"from\":\"left\",\"append\":{\"with\":\"right\"}},{\"sort\":[{\"field\":\"a\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"b\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"c\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"ordered\"}],\"results\":{\"rows\":{\"from\":\"ordered\",\"fields\":[\"a\",\"b\",\"c\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
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
    NeedsInputs(_) => fail("closed independent UNPIVOT input")
  }
}

///|
test "positional UNPIVOT preserves kept values, current labels, duplicate occurrences and authored destinations" {
  for
    source in [
      "SELECT 0 AS a,0 AS b,'anchor' AS c UNION ALL (FROM t |> SELECT x AS kept,-y |> SET kept=7 |> RENAME kept AS renamed |> UNPIVOT INCLUDE NULLS(value FOR label IN(renamed)) AS fresh |> SELECT *) ORDER BY a,b,c",
      "SELECT 0 AS a,0 AS b,'anchor' AS c UNION ALL (FROM t |> SELECT x AS kept,-y |> UNPIVOT INCLUDE NULLS(aql_set_anonymous_4 FOR label IN(kept)) |> WHERE aql_set_anonymous_4>0 |> SELECT *) ORDER BY a,b,c",
      "SELECT 0 AS a,0 AS b,'anchor' AS c UNION ALL (FROM t |> SELECT x AS kept,-y |> UNPIVOT INCLUDE NULLS(value FOR label IN(kept,kept)) |> SELECT *) ORDER BY a,b,c",
      "SELECT 0 AS a,0 AS b,0 AS c,'anchor' AS d UNION ALL (FROM t |> SELECT x AS v,-x AS `V`,y AS target |> UNPIVOT INCLUDE NULLS(value FOR label IN(target)) |> SELECT *) ORDER BY a,b,c,d",
      "SELECT 0 AS a,0 AS b,'anchor' AS c WHERE FALSE UNION ALL (FROM t |> WHERE FALSE |> SELECT x AS kept,-y |> UNPIVOT INCLUDE NULLS(value FOR label IN(kept)) |> SELECT *) ORDER BY a,b,c",
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
      NeedsInputs(_) => fail("closed positional UNPIVOT boundary")
    }
  }
}

///|
test "positional UNPIVOT cannot select anonymous private or ambiguous authored columns" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b,'anchor' AS c UNION ALL (FROM t |> SELECT x AS kept,-y |> UNPIVOT INCLUDE NULLS(value FOR label IN(aql_set_anonymous_4)) |> SELECT *) ORDER BY a,b,c",
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
        "SELECT 0 AS a,0 AS b,'anchor' AS c UNION ALL (FROM t |> SELECT x AS v,-y AS `V` |> UNPIVOT INCLUDE NULLS(value FOR label IN(v)) |> SELECT *) ORDER BY a,b,c",
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
        "SELECT 0 AS a,0 AS b,'anchor' AS c UNION ALL (FROM t |> SELECT x AS kept,-y |> AS old |> UNPIVOT INCLUDE NULLS(value FOR label IN(kept)) |> WHERE old.kept>0 |> SELECT *) ORDER BY a,b,c",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

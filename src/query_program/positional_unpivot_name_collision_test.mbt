///|
test "positional UNPIVOT value name collision retains separate evaluated occurrences" {
  let program = match
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b,0 AS c,'anchor' AS d UNION ALL (FROM t |> SELECT x AS kept,y AS extra,-y |> UNPIVOT INCLUDE NULLS(extra FOR label IN(kept)) |> SELECT *) ORDER BY a,b,c,d",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(DuplicateOutput) => fail("UNPIVOT collision: DuplicateOutput")
    Err(AmbiguousColumn) => fail("UNPIVOT collision: AmbiguousColumn")
    Err(UnsupportedProjection) =>
      fail("UNPIVOT collision: UnsupportedProjection")
    Err(_) => fail("unexpected UNPIVOT collision refusal")
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
    NeedsInputs(_) => fail("closed UNPIVOT collision input")
  }
}

///|
test "positional UNPIVOT label name collision retains separate evaluated occurrences" {
  let program = match
    compile(
      @query.parse_query(
        "SELECT 'anchor' AS a,0 AS b,0 AS c,'anchor' AS d UNION ALL (FROM t |> SELECT x AS kept,'user' AS extra,-y |> UNPIVOT INCLUDE NULLS(value FOR extra IN(kept)) |> SELECT *) ORDER BY a,b,c,d",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(DuplicateOutput) => fail("UNPIVOT collision: DuplicateOutput")
    Err(AmbiguousColumn) => fail("UNPIVOT collision: AmbiguousColumn")
    Err(UnsupportedProjection) =>
      fail("UNPIVOT collision: UnsupportedProjection")
    Err(_) => fail("unexpected UNPIVOT collision refusal")
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
    NeedsInputs(_) => fail("closed UNPIVOT collision input")
  }
}

///|
test "UNPIVOT name collision has an independent ordinary JSON control" {
  let program = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.positional_unpivot_name_collision\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false},\"y\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":1,\"y\":10},{\"x\":2,\"y\":20}]},\"as\":\"input\"},{\"from\":\"input\",\"derive\":{\"neg\":{\"negate\":{\"field\":\"y\"}}}},{\"select\":[{\"kept\":\"x\"},{\"extra\":\"y\"},\"neg\"]},{\"unpivot\":{\"columns\":[\"kept\"],\"keep\":[\"extra\",\"neg\"],\"value_column\":\"expanded\",\"name_column\":\"label\"}},{\"select\":[{\"a\":\"extra\"},{\"b\":\"neg\"},{\"c\":\"expanded\"},{\"d\":\"label\"}],\"as\":\"right\"},{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false},\"b\":{\"type\":\"number\",\"nullable\":false},\"c\":{\"type\":\"number\",\"nullable\":false},\"d\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"a\":0,\"b\":0,\"c\":0,\"d\":\"anchor\"}]},\"as\":\"left\"},{\"from\":\"left\",\"append\":{\"with\":\"right\"}},{\"sort\":[{\"field\":\"a\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"b\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"c\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"d\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"ordered\"}],\"results\":{\"rows\":{\"from\":\"ordered\",\"fields\":[\"a\",\"b\",\"c\",\"d\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
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
    NeedsInputs(_) => fail("closed independent UNPIVOT collision input")
  }
}

///|
test "UNPIVOT duplicate output survives qualified star range" {
  let source = "SELECT 0 AS a,0 AS b,0 AS c,'anchor' AS d UNION ALL (FROM t |> SELECT x AS kept,y AS extra,-y |> UNPIVOT INCLUDE NULLS(extra FOR label IN(kept)) |> AS fresh |> SELECT fresh.*) ORDER BY a,b,c,d"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
    Err(DuplicateOutput) => fail(source + ": DuplicateOutput")
    Err(AmbiguousColumn) => fail(source + ": AmbiguousColumn")
    Err(_) => fail(source + ": unexpected lowering issue")
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
    NeedsInputs(_) => fail("closed UNPIVOT duplicate output scope")
  }
}

///|
test "UNPIVOT duplicate output survives DISTINCT" {
  let source = "SELECT 0 AS a,0 AS b,0 AS c,'anchor' AS d UNION ALL (FROM t |> SELECT x AS kept,y AS extra,-y |> UNPIVOT INCLUDE NULLS(extra FOR label IN(kept)) |> DISTINCT |> SELECT *) ORDER BY a,b,c,d"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
    Err(DuplicateOutput) => fail(source + ": DuplicateOutput")
    Err(AmbiguousColumn) => fail(source + ": AmbiguousColumn")
    Err(_) => fail(source + ": unexpected lowering issue")
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
    NeedsInputs(_) => fail("closed UNPIVOT duplicate output scope")
  }
}

///|
test "UNPIVOT duplicate output survives DROP" {
  let source = "SELECT 0 AS a,'anchor' AS b UNION ALL (FROM t |> SELECT x AS kept,y AS extra,-y |> UNPIVOT INCLUDE NULLS(extra FOR label IN(kept)) |> DROP extra |> SELECT *) ORDER BY a,b"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
    Err(DuplicateOutput) => fail(source + ": DuplicateOutput")
    Err(AmbiguousColumn) => fail(source + ": AmbiguousColumn")
    Err(_) => fail(source + ": unexpected lowering issue")
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
    NeedsInputs(_) => fail("closed UNPIVOT duplicate output scope")
  }
}

///|
test "UNPIVOT duplicate output survives ordinal ORDER" {
  let source = "SELECT 0 AS a,0 AS b,0 AS c,'anchor' AS d UNION ALL (FROM t |> SELECT x AS kept,y AS extra,-y |> UNPIVOT INCLUDE NULLS(extra FOR label IN(kept)) |> ORDER BY 1 DESC |> LIMIT 1 |> SELECT *) ORDER BY a,b,c,d"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
    Err(DuplicateOutput) => fail(source + ": DuplicateOutput")
    Err(AmbiguousColumn) => fail(source + ": AmbiguousColumn")
    Err(_) => fail(source + ": unexpected lowering issue")
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
    NeedsInputs(_) => fail("closed UNPIVOT duplicate output scope")
  }
}

///|
test "UNPIVOT duplicate names remain ambiguous in bare and qualified expression lookup" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b,0 AS c,'anchor' AS d UNION ALL (FROM t |> SELECT x AS kept,y AS extra,-y |> UNPIVOT INCLUDE NULLS(extra FOR label IN(kept)) |> WHERE extra>0 |> SELECT *) ORDER BY a,b,c,d",
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
        "SELECT 0 AS a,0 AS b,0 AS c,'anchor' AS d UNION ALL (FROM t |> SELECT x AS kept,y AS extra,-y |> UNPIVOT INCLUDE NULLS(extra FOR label IN(kept)) |> AS fresh |> WHERE fresh.extra>0 |> SELECT *) ORDER BY a,b,c,d",
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
        "SELECT 0 AS a,0 AS b,0 AS c,'anchor' AS d UNION ALL (FROM t |> SELECT x AS kept,y AS extra,-y |> UNPIVOT INCLUDE NULLS(extra FOR label IN(kept)) |> RENAME extra AS renamed |> SELECT *) ORDER BY a,b,c,d",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(AmbiguousColumn),
  )
}

///|
test "UNPIVOT qualified star retains its immutable row values after a current SET" {
  let program = compile(
    @query.parse_query(
      "SELECT 0 AS a,0 AS b,0 AS c,'anchor' AS d UNION ALL (FROM t |> SELECT x AS kept,y AS extra,-y |> UNPIVOT INCLUDE NULLS(extra FOR label IN(kept)) |> AS fresh |> SET label='changed' |> WHERE fresh.label='kept' |> SELECT fresh.*) ORDER BY a,b,c,d",
      syntax_limits(),
    ).unwrap(),
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
    NeedsInputs(_) => fail("closed immutable UNPIVOT star")
  }
}

///|
test "UNPIVOT output stars do not revive displaced or projected-away ranges" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 'anchor' AS a UNION ALL (FROM t |> SELECT x AS kept,y AS extra,-y |> UNPIVOT INCLUDE NULLS(extra FOR label IN(kept)) |> AS old |> AS fresh |> SELECT old.*) ORDER BY a",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnsupportedProjection),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 'anchor' AS a UNION ALL (FROM t |> SELECT x AS kept,y AS extra,-y |> UNPIVOT INCLUDE NULLS(extra FOR label IN(kept)) |> AS old |> SELECT label |> SELECT old.*) ORDER BY a",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnsupportedProjection),
  )
}

///|
fn positional_pivot_context() -> Context {
  let seed = unnest_value_cursor(
    "{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false},\"y\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":1,\"y\":10},{\"x\":2,\"y\":20},{\"x\":3,\"y\":10}]},\"as\":\"t\"}",
  )
  {
    ..fixture_context(),
    inputs: [
      {
        relation: [{ value: "t", quoted: false, }],
        name: "t",
        source: GeneratedValues(seed),
        visible_fields: ["x", "y"],
        graph_bindings: [],
      },
    ],
  }
}

///|
test "PIVOT retains the anonymous implicit grouping key in a positional operand" {
  let program = match
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS amount,-y,'A' AS axis |> PIVOT(SUM(amount) AS total FOR axis IN('A')) |> SELECT *) ORDER BY a,b",
        syntax_limits(),
      ).unwrap(),
      positional_pivot_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("PIVOT lost anonymous grouping key: UnsupportedProjection")
    Err(DuplicateOutput) =>
      fail("PIVOT lost grouping occurrences: DuplicateOutput")
    Err(_) => fail("unexpected positional PIVOT refusal")
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
    NeedsInputs(_) => fail("closed positional PIVOT source")
  }
}

///|
test "positional PIVOT has an independently authored ordinary JSON control" {
  let program = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.positional_pivot\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false},\"y\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":1,\"y\":10},{\"x\":2,\"y\":20},{\"x\":3,\"y\":10}]},\"as\":\"input\"},{\"from\":\"input\",\"derive\":{\"neg\":{\"negate\":{\"field\":\"y\"}},\"axis\":{\"literal\":\"A\"}}},{\"select\":[{\"amount\":\"x\"},\"neg\",\"axis\"]},{\"pivot\":{\"index\":[\"neg\"],\"column\":\"axis\",\"value\":\"amount\",\"values\":[\"A\"],\"aggregate\":\"sum\"}},{\"select\":[{\"a\":\"neg\"},{\"b\":\"A\"}],\"as\":\"right\"},{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false},\"b\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"a\":0,\"b\":0}]},\"as\":\"left\"},{\"from\":\"left\",\"append\":{\"with\":\"right\"}},{\"sort\":[{\"field\":\"a\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"b\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"ordered\"}],\"results\":{\"rows\":{\"from\":\"ordered\",\"fields\":[\"a\",\"b\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
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
    NeedsInputs(_) => fail("closed independent PIVOT input")
  }
}

///|
test "positional PIVOT preserves immutable aggregate receiver" {
  let source = "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS amount,-y,'A' AS axis |> AS r |> SET amount=7 |> PIVOT(SUM(r.amount) AS total FOR axis IN('A')) |> SELECT *) ORDER BY a,b,c"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      positional_pivot_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
    Err(UnsupportedSet) => fail(source + ": UnsupportedSet")
    Err(DuplicateOutput) => fail(source + ": DuplicateOutput")
    Err(UnknownColumn) => fail(source + ": UnknownColumn")
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
    NeedsInputs(_) => fail("closed positional PIVOT boundary")
  }
}

///|
test "positional PIVOT preserves duplicate grouping occurrences" {
  let source = "SELECT 0 AS a,0 AS b,0 AS c UNION ALL (FROM t |> SELECT x AS v,-x AS `V`,y AS amount,'A' AS axis |> PIVOT(SUM(amount) AS total FOR axis IN('A')) |> SELECT *) ORDER BY a,b,c"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      positional_pivot_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
    Err(UnsupportedSet) => fail(source + ": UnsupportedSet")
    Err(DuplicateOutput) => fail(source + ": DuplicateOutput")
    Err(UnknownColumn) => fail(source + ": UnknownColumn")
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
    NeedsInputs(_) => fail("closed positional PIVOT boundary")
  }
}

///|
test "positional PIVOT preserves authored private-shaped destination" {
  let source = "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS amount,-y,'A' AS axis |> PIVOT(SUM(amount) FOR axis IN('A' AS aql_set_anonymous_5)) |> SELECT *) ORDER BY a,b"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      positional_pivot_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
    Err(UnsupportedSet) => fail(source + ": UnsupportedSet")
    Err(DuplicateOutput) => fail(source + ": DuplicateOutput")
    Err(UnknownColumn) => fail(source + ": UnknownColumn")
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
    NeedsInputs(_) => fail("closed positional PIVOT boundary")
  }
}

///|
test "positional PIVOT preserves fresh output star" {
  let source = "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS amount,-y,'A' AS axis |> PIVOT(SUM(amount) AS total FOR axis IN('A')) AS fresh |> SELECT fresh.*) ORDER BY a,b"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      positional_pivot_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
    Err(UnsupportedSet) => fail(source + ": UnsupportedSet")
    Err(DuplicateOutput) => fail(source + ": DuplicateOutput")
    Err(UnknownColumn) => fail(source + ": UnknownColumn")
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
    NeedsInputs(_) => fail("closed positional PIVOT boundary")
  }
}

///|
test "positional PIVOT preserves typed empty input" {
  let source = "SELECT 0 AS a,0 AS b WHERE FALSE UNION ALL (FROM t |> WHERE FALSE |> SELECT x AS amount,-y,'A' AS axis |> PIVOT(SUM(amount) AS total FOR axis IN('A')) |> SELECT *) ORDER BY a,b"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      positional_pivot_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) => fail(source + ": UnsupportedProjection")
    Err(UnsupportedSet) => fail(source + ": UnsupportedSet")
    Err(DuplicateOutput) => fail(source + ": DuplicateOutput")
    Err(UnknownColumn) => fail(source + ": UnknownColumn")
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
    NeedsInputs(_) => fail("closed positional PIVOT boundary")
  }
}

///|
test "positional PIVOT refuses private or ambiguous arguments and logical output collisions" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS amount,-y,'A' AS axis |> PIVOT(SUM(aql_set_anonymous_5) FOR axis IN('A')) |> SELECT *) ORDER BY a,b",
        syntax_limits(),
      ).unwrap(),
      positional_pivot_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS v,-x AS `V`,y AS amount,'A' AS axis |> PIVOT(SUM(v) FOR axis IN('A')) |> SELECT *) ORDER BY a,b",
        syntax_limits(),
      ).unwrap(),
      positional_pivot_context(),
      construction_limits(),
    )
    is Err(AmbiguousColumn),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS v,-x AS `V`,y AS amount,'A' AS axis |> AS r |> PIVOT(SUM(r.v) FOR axis IN('A')) |> SELECT *) ORDER BY a,b",
        syntax_limits(),
      ).unwrap(),
      positional_pivot_context(),
      construction_limits(),
    )
    is Err(AmbiguousColumn),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS v,-x AS `V`,y AS amount,'A' AS axis |> PIVOT(SUM(amount) FOR axis IN('A' AS v)) |> SELECT *) ORDER BY a,b",
        syntax_limits(),
      ).unwrap(),
      positional_pivot_context(),
      construction_limits(),
    )
    is Err(DuplicateOutput),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT 0 AS a,0 AS b UNION ALL (FROM t |> SELECT x AS amount,-y,'A' AS axis |> PIVOT(SUM(y) FOR axis IN('A')) |> SELECT *) ORDER BY a,b",
        syntax_limits(),
      ).unwrap(),
      positional_pivot_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
}

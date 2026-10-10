///|
test "window replacement retains an earlier anonymous positional value" {
  // For x=1,2 the independent (a,b) rows are (0,0),(1,-2),(2,-1).
  let source = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> SELECT * REPLACE (ROW_NUMBER() OVER (ORDER BY kept DESC) AS kept)) ORDER BY a, b"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("window replacement erased the earlier positional role")
    Err(UnsupportedAnalytic) =>
      fail("window replacement lost its current input scope")
    Err(_) => fail("unexpected window replacement refusal")
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
    NeedsInputs(_) => fail("closed window replacement")
  }
}

///|
test "independent window replacement JSON uses the ordinary analytic input" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.positional_window_replacement","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1},{"x":2}]},"as":"input"},{"from":"input","derive":{"neg":{"negate":{"field":"x"}}}},{"select":[{"kept":"x"},"neg"]},{"analytic":{"partition_by":[],"order_by":[{"field":"kept","dir":"desc","nulls":"last"}],"functions":{"rank":{"fn":"row_number"}}}},{"select":[{"a":"rank"},{"b":"neg"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false},"b":{"type":"number","nullable":false}},"rows":[{"a":0,"b":0}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"},{"field":"b","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(
      expected,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("independent analytic control has no acquisition")
  }
}

///|
test "window replacement composes current names expression frames and named windows" {
  for
    source in [
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> SELECT * REPLACE (ROW_NUMBER() OVER (ORDER BY kept DESC) + 5 AS kept)) ORDER BY a, b",
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> SELECT * REPLACE (ROW_NUMBER() OVER w AS `KEPT`) WINDOW w AS (ORDER BY kept DESC) |> SELECT * |> WHERE kept > 1) ORDER BY a, b",
      "SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM t |> SELECT x AS first, y AS second, -x |> SELECT * REPLACE (ROW_NUMBER() OVER (ORDER BY first DESC) AS first, ROW_NUMBER() OVER (ORDER BY second) AS second)) ORDER BY a, b, c",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        actual,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("closed window replacement composition")
    }
  }
}

///|
test "window replacement never exposes private receivers or dropped ranges" {
  let head = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> AS old |> SELECT x AS kept, -x |> SELECT * REPLACE (ROW_NUMBER() OVER (ORDER BY "
  for receiver in ["aql_set_anonymous_4", "`AQL_SET_ANONYMOUS_4`"] {
    assert_true(
      compile(
        @query.parse_query(
          head + receiver + ") AS kept)) ORDER BY a, b",
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=receiver,
    )
  }
  for receiver in ["old.x", "x", "t.x"] {
    // Simple window ORDER references use the existing analytic field resolver.
    // Its missing-field diagnostic is UnknownColumn, not scalar-expression typing.
    assert_true(
      compile(
        @query.parse_query(
          head + receiver + ") AS kept)) ORDER BY a, b",
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=receiver,
    )
  }
}

///|
test "window replacement retains ambiguity of duplicate authored inputs" {
  let source = "SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM t |> SELECT x AS v, -x AS `V`, y AS kept |> SELECT * REPLACE (ROW_NUMBER() OVER (ORDER BY v) AS kept)) ORDER BY a, b, c"
  assert_true(
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(AmbiguousColumn),
  )
}

///|
test "anonymous positional operand preserves its postprojection filter" {
  let source = "SELECT 0 AS a UNION ALL (FROM t |> SELECT -x |> WHERE FALSE) ORDER BY a"
  let actual = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail(
        "a column-preserving postprojection filter loses the positional output role",
      )
    Err(_) => fail("another lowering refusal")
  }
  match
    @check.check_parsed(
      actual,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the input is closed Values")
  }
}

///|
test "filtered positional output keeps named aliases and evaluated windows" {
  for
    source in [
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> AS original |> SELECT x AS kept, -x |> WHERE kept = 1) ORDER BY a, b",
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT ROW_NUMBER() OVER (ORDER BY x), -x |> WHERE TRUE |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a, b",
      "SELECT 0 AS a UNION ALL (FROM t |> SELECT -x |> WHERE CAST(NULL AS BOOL)) ORDER BY a",
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS v, -x AS `V` |> WHERE TRUE |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a, b",
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
      NeedsInputs(_) => fail("the filtered operand uses closed Values")
    }
  }
}

///|
test "postprojection filter cannot recover discarded fields or old input ranges" {
  for receiver in ["x", "original.x"] {
    let source = "SELECT 0 AS a UNION ALL (FROM t |> AS original |> SELECT -x |> WHERE " +
      receiver +
      " > 0) ORDER BY a"
    match
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      ) {
      Err(Expression({ issue: @expression.UnknownReference, .. })) => ()
      Ok(_) => fail("the filter recovered a discarded input: " + receiver)
      Err(_) => fail("the filter failed for another reason: " + receiver)
    }
  }
}

///|
test "postprojection filter refuses private and ambiguous output receivers" {
  let accepted = compile(
    @query.parse_query(
      "SELECT 0 AS a UNION ALL (FROM t |> AS original |> SELECT -x |> WHERE TRUE) ORDER BY a",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(accepted).contains("aql_set_anonymous_3"),
    msg=semantic(accepted),
  )
  for
    receiver in [
      "aql_set_anonymous_3", "`AQL_SET_ANONYMOUS_3`", "aql_set_anonymous_3.member",
    ] {
    let source = "SELECT 0 AS a UNION ALL (FROM t |> AS original |> SELECT -x |> WHERE " +
      receiver +
      " > 0) ORDER BY a"
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=receiver,
    )
  }
  for receiver in ["v", "`V`", "v.member"] {
    let source = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS v, -x AS `V` |> WHERE " +
      receiver +
      " > 0) ORDER BY a, b"
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(AmbiguousColumn),
      msg=receiver,
    )
  }
}

///|
test "independent anonymous filtered operand is an ordinary checked Program" {
  // Independently authored: the right filter removes every -x row; the left
  // zero remains. Filtering must stay on the right operand, before append.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.positional_filter","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1},{"x":2}]},"as":"input"},{"from":"input","derive":{"neg":{"negate":{"field":"x"}}}},{"select":[{"a":"neg"}]},{"filter":{"literal":false},"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false}},"rows":[{"a":0}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
    NeedsInputs(_) => fail("the independent JSON has no acquisition")
  }
}

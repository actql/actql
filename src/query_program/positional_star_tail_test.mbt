///|
test "anonymous positional value survives a later ordinary star" {
  let source = "SELECT 0 AS a UNION ALL (FROM t |> SELECT -x |> SELECT *) ORDER BY a"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("ordinary star lost the anonymous positional value")
    Err(_) => fail("unexpected lowering refusal")
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
    NeedsInputs(_) => fail("closed input")
  }
}

///|
test "independent star-preserved positional value uses the ordinary Program" {
  // A star selects the evaluated -x once; independent x=1,2 gives -2,-1,0.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.positional_star","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1},{"x":2}]},"as":"input"},{"from":"input","derive":{"neg":{"negate":{"field":"x"}}}},{"select":["neg"]},{"select":["neg"]},{"select":[{"a":"neg"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false}},"rows":[{"a":0}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
    NeedsInputs(_) => fail("independent control has no acquisition")
  }
}

///|
test "positional star chains preserve ordinals analytics aggregates and duplicates" {
  for
    source in [
      "SELECT 0 AS a UNION ALL (FROM t |> SELECT -x |> SELECT * |> SELECT * |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a",
      "SELECT 0 AS a UNION ALL (FROM t |> SELECT -x |> SELECT DISTINCT *) ORDER BY a",
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS v, -x AS `V` |> SELECT * |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a, b",
      "SELECT 0 AS a UNION ALL (FROM t |> SELECT ROW_NUMBER() OVER (ORDER BY x) |> SELECT * |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a",
      "SELECT 0 AS a, 0 AS b UNION ALL (SELECT SUM(x), COUNT(x) FROM t |> SELECT *) ORDER BY a, b",
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
      NeedsInputs(_) => fail("closed star operand")
    }
  }
}

///|
test "star never gives generated names or duplicate aliases a receiver" {
  let accepted = compile(
    @query.parse_query(
      "SELECT 0 AS a UNION ALL (FROM t |> SELECT -x |> SELECT *) ORDER BY a",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_true(semantic(accepted).contains("aql_set_anonymous_2"))
  for
    receiver in [
      "aql_set_anonymous_2", "`AQL_SET_ANONYMOUS_2`", "aql_set_anonymous_2.member",
    ] {
    let source = "SELECT 0 AS a UNION ALL (FROM t |> SELECT -x |> SELECT * |> ORDER BY " +
      receiver +
      ") ORDER BY a"
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
    let source = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS v, -x AS `V` |> SELECT * |> ORDER BY " +
      receiver +
      ") ORDER BY a, b"
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
test "ordinary star cannot restore an earlier input range" {
  let star = "SELECT 0 AS a UNION ALL (FROM t |> AS old |> SELECT x AS kept |> SELECT old.*) ORDER BY a"
  assert_true(
    compile(
      @query.parse_query(star, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
  let order = "SELECT 0 AS a UNION ALL (FROM t |> AS old |> SELECT -x |> SELECT * |> ORDER BY old.x) ORDER BY a"
  assert_true(
    compile(
      @query.parse_query(order, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

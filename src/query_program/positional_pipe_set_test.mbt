///|
test "positional SET retains the prior anonymous value" {
  let source = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> SET kept = kept + 10) ORDER BY a, b"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("SET erased the earlier anonymous positional role")
    Err(_) => fail("unexpected SET refusal")
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
    NeedsInputs(_) => fail("closed SET operand")
  }
}

///|
test "independent SET control retains evaluated negation and changes only kept" {
  // Independent x=1,2 gives (a,b)=(0,0),(11,-1),(12,-2).
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.positional_replacement","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1},{"x":2}]},"as":"input"},{"from":"input","derive":{"neg":{"negate":{"field":"x"}}}},{"select":[{"kept":"x"},"neg"]},{"derive":{"changed":{"add":[{"field":"kept"},{"literal":10}]}}},{"select":[{"kept":"changed"},"neg"]},{"select":[{"a":"kept"},{"b":"neg"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false},"b":{"type":"number","nullable":false}},"rows":[{"a":0,"b":0}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"},{"field":"b","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
test "positional SET composes current aliases ordinals and simultaneous siblings" {
  for
    source in [
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> SET `KEPT` = kept + 10 |> WHERE kept > 11 |> SELECT * |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a, b",
      "SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM t |> SELECT x AS first, y AS second, -x |> SET first = second, second = first) ORDER BY a, b, c",
      "SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM t |> SELECT x AS v, -x AS `V`, x + 10 AS kept |> SET kept = kept + 1) ORDER BY a, b, c",
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> SET kept = kept + 10 |> SET kept = kept + 1) ORDER BY a, b",
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS x, -x |> SET x = -x |> ORDER BY -x |> LIMIT 1) ORDER BY a, b",
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
      NeedsInputs(_) => fail("closed SET chain")
    }
  }
}

///|
test "positional SET cannot target or read a private anonymous slot" {
  let head = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> SET "
  for
    assignment in [
      "aql_set_anonymous_4 = 0", "`AQL_SET_ANONYMOUS_4` = 0", "kept = aql_set_anonymous_4 + 1",
      "kept = aql_set_anonymous_4.member",
    ] {
    assert_true(
      compile(
        @query.parse_query(
          head + assignment + ") ORDER BY a, b",
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=assignment,
    )
  }
}

///|
test "positional SET preserves duplicate alias ambiguity and unique assignments" {
  let head = "SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM t |> SELECT x AS v, -x AS `V`, x + 10 AS kept |> SET "
  for assignment in ["v = 0", "`V` = 0", "kept = v + 1", "kept = v.member"] {
    assert_true(
      compile(
        @query.parse_query(
          head + assignment + ") ORDER BY a, b, c",
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(AmbiguousColumn),
      msg=assignment,
    )
  }
  let duplicate = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> SET kept = 1, `KEPT` = 2) ORDER BY a, b"
  assert_true(
    compile(
      @query.parse_query(duplicate, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(DuplicateOutput),
  )
}

///|
test "positional SET cannot recover the SELECT input or its old range" {
  for receiver in ["x", "t.x", "old.x"] {
    let source = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> AS old |> SELECT x AS kept, -x |> SET kept = " +
      receiver +
      ") ORDER BY a, b"
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=receiver,
    )
  }
}

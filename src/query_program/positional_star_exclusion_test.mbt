///|
test "positional star exclusion retains the anonymous column" {
  let source = "SELECT 0 AS a UNION ALL (FROM t |> SELECT x AS kept, -x |> SELECT * EXCEPT (kept)) ORDER BY a"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("named exclusion erased the anonymous positional role")
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
    NeedsInputs(_) => fail("closed Values")
  }
}

///|
test "independent named exclusion uses ordinary evaluated column projection" {
  // Independent input x=1,2; drop kept while retaining the evaluated -x.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.positional_exclusion","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1},{"x":2}]},"as":"input"},{"from":"input","derive":{"neg":{"negate":{"field":"x"}}}},{"select":[{"kept":"x"},"neg"]},{"select":["neg"]},{"select":[{"a":"neg"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false}},"rows":[{"a":0}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
    NeedsInputs(_) => fail("independent JSON has no acquisition")
  }
}

///|
test "exclusion removes every duplicate authored alias and retains anonymous ordinal" {
  let source = "SELECT 0 AS a UNION ALL (FROM t |> SELECT x AS v, -x AS `V`, x + 10 |> SELECT * EXCEPT (v)) ORDER BY a"
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
    NeedsInputs(_) => fail("closed duplicate alias input")
  }
}

///|
test "named exclusion composes with stars filters ordinals windows and aggregates" {
  for
    source in [
      "SELECT 0 AS a UNION ALL (FROM t |> SELECT x AS kept, -x |> SELECT * EXCEPT (`KEPT`) |> SELECT * |> WHERE TRUE |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a",
      "SELECT 0 AS a UNION ALL (FROM t |> SELECT x AS first, x + 1 AS second, -x |> SELECT * EXCEPT (first) |> SELECT * EXCEPT (second)) ORDER BY a",
      "SELECT 0 AS a UNION ALL (FROM t |> SELECT x AS kept, -x |> SELECT DISTINCT * EXCEPT (kept)) ORDER BY a",
      "SELECT 0 AS a UNION ALL (FROM t |> SELECT x AS kept, ROW_NUMBER() OVER (ORDER BY x) |> SELECT * EXCEPT (kept) |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a",
      "SELECT 0 AS a UNION ALL (SELECT COUNT(x) AS kept, SUM(x) FROM t |> SELECT * EXCEPT (kept)) ORDER BY a",
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
      NeedsInputs(_) => fail("closed exclusion operand")
    }
  }
}

///|
test "exclusion cannot address private names or absent named columns" {
  let head = "SELECT 0 AS a UNION ALL (FROM t |> SELECT x AS kept, -x |> SELECT * EXCEPT ("
  let accepted = compile(
    @query.parse_query(head + "kept)) ORDER BY a", syntax_limits()).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(accepted).contains("aql_set_anonymous_4"),
    msg=semantic(accepted),
  )
  for excluded in ["aql_set_anonymous_4", "`AQL_SET_ANONYMOUS_3`", "missing"] {
    assert_true(
      compile(
        @query.parse_query(head + excluded + ")) ORDER BY a", syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=excluded,
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        head + "kept) |> SELECT * EXCEPT (kept)) ORDER BY a",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
}

///|
test "excluded aliases and earlier ranges do not survive the new scope" {
  for receiver in ["kept", "old.x"] {
    let source = "SELECT 0 AS a UNION ALL (FROM t |> AS old |> SELECT x AS kept, -x |> SELECT * EXCEPT (kept) |> ORDER BY " +
      receiver +
      ") ORDER BY a"
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
  let dropped = "SELECT 0 AS a UNION ALL (FROM t |> SELECT x AS v, -x AS `V`, x + 10 |> SELECT * EXCEPT (v) |> ORDER BY v) ORDER BY a"
  assert_true(
    compile(
      @query.parse_query(dropped, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

///|
test "retained duplicate aliases stay ambiguous after another column is excluded" {
  let source = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS v, -x AS `V`, x + 10 AS dropped |> SELECT * EXCEPT (dropped) |> ORDER BY v) ORDER BY a, b"
  assert_true(
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(AmbiguousColumn),
  )
}

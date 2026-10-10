///|
test "positional DROP retains the earlier anonymous value" {
  let source = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, y AS removed, -x |> DROP removed) ORDER BY a, b"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("DROP erased the earlier anonymous positional role")
    Err(_) => fail("unexpected DROP refusal")
  }
  assert_true(semantic(program).contains("\"aql_set_anonymous_6\""))
  match
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed DROP operand")
  }
}

///|
test "independent DROP control preserves negation and ordinal alignment" {
  // Authored independently: x=1,2 gives (a,b)=(0,0),(1,-1),(2,-2).
  let control = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.positional_drop","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"input"},{"from":"input","derive":{"neg":{"negate":{"field":"x"}}}},{"select":[{"kept":"x"},{"removed":"y"},"neg"]},{"drop":["removed"]},{"select":[{"a":"kept"},{"b":"neg"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false},"b":{"type":"number","nullable":false}},"rows":[{"a":0,"b":0}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"},{"field":"b","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(
      control,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("independent DROP control has no acquisition")
  }
}

///|
test "positional DROP composes quoted names duplicates stars and ordinal LIMIT" {
  for
    source in [
      "SELECT 0 AS a UNION ALL (FROM t |> SELECT x AS v, -x AS `V`, x + 10 |> DROP `v`) ORDER BY a",
      "SELECT 0 AS a UNION ALL (FROM t |> SELECT x AS first, y AS second, -x |> DROP first |> DROP `SECOND` |> SELECT * |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a",
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS v, -x AS `V`, y AS removed |> DROP removed) ORDER BY a, b",
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, y AS removed, -x |> DROP removed |> WHERE kept > 1 |> ORDER BY -kept |> LIMIT 1) ORDER BY a, b",
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
      NeedsInputs(_) => fail("closed positional DROP chain")
    }
  }
}

///|
test "positional DROP refuses private names missing targets and repeated targets" {
  let head = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, y AS removed, -x |> DROP "
  for target in ["aql_set_anonymous_6", "`AQL_SET_ANONYMOUS_6`", "missing"] {
    assert_true(
      compile(
        @query.parse_query(head + target + ") ORDER BY a, b", syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=target,
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        head + "removed, `REMOVED`) ORDER BY a, b",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(DuplicateOutput),
  )
}

///|
test "positional DROP does not restore removed names or SELECT input ranges" {
  for
    source in [
      "SELECT 0 AS a UNION ALL (FROM t |> SELECT x AS kept, -x |> DROP kept |> WHERE kept > 0) ORDER BY a",
      "SELECT 0 AS a UNION ALL (FROM t |> SELECT x AS x, -x |> DROP x |> ORDER BY x) ORDER BY a",
      "SELECT 0 AS a UNION ALL (FROM t |> SELECT x AS v, -x AS `V`, x + 10 |> DROP v |> WHERE v > 0) ORDER BY a",
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> AS old |> SELECT x AS kept, y AS removed, -x |> DROP removed |> WHERE old.x > 0) ORDER BY a, b",
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

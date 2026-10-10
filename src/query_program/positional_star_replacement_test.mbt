///|
test "positional REPLACE retains the prior anonymous value" {
  let source = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> SELECT * REPLACE (kept + 10 AS kept)) ORDER BY a, b"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("REPLACE erased the earlier anonymous positional role")
    Err(_) => fail("unexpected replacement refusal")
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
    NeedsInputs(_) => fail("closed replacement operand")
  }
}

///|
test "independent REPLACE control retains evaluated negation and changes only kept" {
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
test "replacement chains preserve ordinals simultaneous inputs exclusions and duplicates" {
  for
    source in [
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> SELECT * REPLACE (kept + 10 AS `KEPT`) |> SELECT * |> WHERE kept > 11 |> ORDER BY 1 DESC |> LIMIT 1) ORDER BY a, b",
      "SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM t |> SELECT x AS first, y AS second, -x |> SELECT * REPLACE (second AS first, first AS second)) ORDER BY a, b, c",
      "SELECT 0 AS a UNION ALL (FROM t |> SELECT x AS dropped, y AS kept, -x |> SELECT * EXCEPT (dropped) REPLACE (kept + 1 AS kept) |> SELECT * EXCEPT (kept)) ORDER BY a",
      "SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM t |> SELECT x AS v, -x AS `V`, x + 10 AS kept |> SELECT * REPLACE (kept + 1 AS kept)) ORDER BY a, b, c",
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> SELECT DISTINCT * REPLACE (kept + 10 AS kept)) ORDER BY a, b",
      "SELECT 'anchor' AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> SELECT * REPLACE ('changed' AS kept)) ORDER BY a, b",
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
      NeedsInputs(_) => fail("closed replacement chain")
    }
  }
}

///|
test "replacement cannot target or read an anonymous private slot" {
  let head = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> SELECT * REPLACE ("
  let accepted = compile(
    @query.parse_query(
      head + "kept + 10 AS kept)) ORDER BY a, b",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_true(semantic(accepted).contains("aql_set_anonymous_4"))
  for
    value in [
      "0 AS aql_set_anonymous_4", "0 AS `AQL_SET_ANONYMOUS_4`", "kept + aql_set_anonymous_4 AS kept",
      "COALESCE(aql_set_anonymous_4, kept) AS kept", "aql_set_anonymous_4.member AS kept",
    ] {
    assert_true(
      compile(
        @query.parse_query(head + value + ")) ORDER BY a, b", syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=value,
    )
  }
}

///|
test "replacement checks duplicate targets and receivers against authored names" {
  let head = "SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM t |> SELECT x AS v, -x AS `V`, x + 10 AS kept |> SELECT * REPLACE ("
  for value in ["0 AS v", "0 AS `V`", "v + 1 AS kept", "v.member AS kept"] {
    assert_true(
      compile(
        @query.parse_query(
          head + value + ")) ORDER BY a, b, c",
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(AmbiguousColumn),
      msg=value,
    )
  }
  let retained = head + "kept + 1 AS kept) |> ORDER BY v) ORDER BY a, b, c"
  assert_true(
    compile(
      @query.parse_query(retained, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(AmbiguousColumn),
  )
}

///|
test "replacement cannot revive a dropped target or an earlier input range" {
  let dropped = "SELECT 0 AS a UNION ALL (FROM t |> SELECT x AS kept, -x |> SELECT * EXCEPT (kept) REPLACE (0 AS kept)) ORDER BY a"
  assert_true(
    compile(
      @query.parse_query(dropped, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
  let old = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> AS old |> SELECT x AS kept, -x |> SELECT * REPLACE (old.x AS kept)) ORDER BY a, b"
  assert_true(
    compile(
      @query.parse_query(old, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

///|
test "replacement reads only the current named projection and has unique targets" {
  for receiver in ["x", "t.x"] {
    let source = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> SELECT * REPLACE (" +
      receiver +
      " AS kept)) ORDER BY a, b"
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
  let source = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> SELECT * REPLACE (1 AS kept, 2 AS `KEPT`)) ORDER BY a, b"
  assert_true(
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(DuplicateOutput),
  )
}

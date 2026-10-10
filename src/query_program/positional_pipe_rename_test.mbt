///|
test "positional RENAME retains the earlier anonymous value" {
  let source = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> RENAME kept AS renamed) ORDER BY a, b"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("RENAME erased the earlier anonymous positional role")
    Err(_) => fail("unexpected RENAME refusal")
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
    NeedsInputs(_) => fail("closed RENAME operand")
  }
}

///|
test "independent RENAME control preserves negation and ordinal alignment" {
  // Authored independently: x=1,2 gives (a,b)=(0,0),(1,-1),(2,-2).
  let control = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.positional_rename","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1},{"x":2}]},"as":"input"},{"from":"input","derive":{"neg":{"negate":{"field":"x"}}}},{"select":[{"kept":"x"},"neg"]},{"select":[{"renamed":"kept"},"neg"]},{"select":[{"a":"renamed"},{"b":"neg"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false},"b":{"type":"number","nullable":false}},"rows":[{"a":0,"b":0}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"},{"field":"b","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
    NeedsInputs(_) => fail("independent RENAME control has no acquisition")
  }
}

///|
test "positional RENAME retains current aliases and later private-shaped destinations" {
  for
    source in [
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT -x AS kept, x + 10 |> RENAME kept AS x |> WHERE x < 0 |> ORDER BY -x |> LIMIT 1) ORDER BY a, b",
      "SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM t |> SELECT x AS kept, y AS other, -x |> RENAME other AS kept |> ORDER BY 1) ORDER BY a, b, c",
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> RENAME kept AS aql_set_anonymous_4 |> WHERE aql_set_anonymous_4 > 0) ORDER BY a, b",
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> RENAME kept AS `AQL_SET_ANONYMOUS_4` |> WHERE aql_set_anonymous_4 > 0) ORDER BY a, b",
      "SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM t |> SELECT x AS v, -x AS `V`, x + 10 AS kept |> RENAME kept AS `AQL_SET_DUPLICATE_5` |> WHERE aql_set_duplicate_5 > 11) ORDER BY a, b, c",
      "SELECT 0 AS a UNION ALL (FROM t |> SELECT x AS first, y AS second, -x |> RENAME first AS kept, second AS kept |> DROP kept) ORDER BY a",
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
      NeedsInputs(_) => fail("closed RENAME boundary")
    }
  }
}

///|
test "positional RENAME refuses private missing and repeated targets" {
  let head = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> RENAME "
  for
    target in [
      "aql_set_anonymous_4 AS next", "`AQL_SET_ANONYMOUS_4` AS next", "missing AS next",
    ] {
    assert_true(
      compile(
        @query.parse_query(head + target + ") ORDER BY a,b", syntax_limits()).unwrap(),
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
        head + "kept AS first, `KEPT` AS second) ORDER BY a,b",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(DuplicateOutput),
  )
}

///|
test "positional RENAME keeps original and newly introduced receiver ambiguity" {
  let original = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS v, -x AS `V` |> RENAME v AS changed) ORDER BY a,b"
  assert_true(
    compile(
      @query.parse_query(original, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(AmbiguousColumn),
  )
  let head = "SELECT 0 AS a, 0 AS b, 0 AS c UNION ALL (FROM t |> SELECT x AS kept, y AS other, -x |> RENAME other AS kept "
  for
    tail in [
      "|> WHERE kept > 0", "|> WHERE kept.member > 0", "|> ORDER BY kept", "|> RENAME kept AS changed",
      "|> SET kept = 0",
    ] {
    assert_true(
      compile(
        @query.parse_query(head + tail + ") ORDER BY a,b,c", syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(AmbiguousColumn),
      msg=tail,
    )
  }
}

///|
test "positional RENAME does not restore removed names input ranges or private values" {
  for
    source in [
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> RENAME kept AS renamed |> WHERE kept > 0) ORDER BY a,b",
      "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> AS old |> SELECT x AS kept, -x |> RENAME kept AS renamed |> WHERE old.x > 0) ORDER BY a,b",
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
  let public_name = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> RENAME kept AS aql_set_anonymous_4 |> WHERE aql_set_anonymous_4 > 0) ORDER BY a,b"
  let actual = compile(
    @query.parse_query(public_name, syntax_limits()).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  assert_true(semantic(actual).contains("\"aql_set_anonymous_5\""))
  let private_reference = "SELECT 0 AS a, 0 AS b UNION ALL (FROM t |> SELECT x AS kept, -x |> RENAME kept AS aql_set_anonymous_4 |> WHERE aql_set_anonymous_5 > 0) ORDER BY a,b"
  assert_true(
    compile(
      @query.parse_query(private_reference, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
}

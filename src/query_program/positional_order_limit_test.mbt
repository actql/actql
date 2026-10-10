///|
test "positional anonymous scalar retains explicit inner order and limit" {
  let source = "SELECT 0 AS a UNION ALL (SELECT -x FROM t ORDER BY x DESC LIMIT 1) ORDER BY a"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("anonymous scalar refused before preserving ORDER BY x DESC LIMIT 1")
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
    NeedsInputs(_) => fail("closed two-row input")
  }
  let wire = semantic(program)
  assert_eq(wire.split("\"negate\":").length(), 2)
  assert_true(
    wire.contains(
      "\"sort\":[{\"dir\":\"desc\",\"field\":\"x\",\"nulls\":\"last\"}]",
    ),
  )
  assert_true(wire.contains("\"take\":{\"count\":1,\"offset\":0}"))
  assert_true(wire.contains("\"fields\":[\"a\"]"))
}

///|
test "positional anonymous window retains explicit inner order and limit" {
  let source = "SELECT 0 AS a UNION ALL (SELECT ROW_NUMBER() OVER (ORDER BY x) FROM t ORDER BY x DESC LIMIT 1) ORDER BY a"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("anonymous window refused before preserving ORDER BY x DESC LIMIT 1")
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
    NeedsInputs(_) => fail("closed two-row input")
  }
}

///|
test "independent ordered limited scalar control is ordinarily checked" {
  // Independently authored: input x=1,2; descending x then LIMIT 1 selects
  // x=2, hence -x=-2. Combined ascending output is a=-2,0.
  let program = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.positional_order_limit","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1},{"x":2}]},"as":"input"},{"from":"input","derive":{"neg":{"negate":{"field":"x"}}}},{"sort":[{"field":"x","dir":"desc","nulls":"last"}]},{"take":{"count":1,"offset":0}},{"select":[{"a":"neg"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false}},"rows":[{"a":0}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
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
    NeedsInputs(_) => fail("the JSON control is closed")
  }
}

///|
test "positional tails preserve ordinal order offset aggregate and alias scopes" {
  for
    source in [
      "SELECT 0 AS a UNION ALL (SELECT -x FROM t ORDER BY 1 DESC LIMIT 1 OFFSET 1) ORDER BY a",
      "SELECT 0 AS a UNION ALL (SELECT ROW_NUMBER() OVER (ORDER BY x) FROM t ORDER BY 1 DESC LIMIT 1) ORDER BY a",
      "SELECT 0 AS a, 0 AS b UNION ALL (SELECT SUM(x), COUNT(x) FROM t ORDER BY 1 DESC LIMIT 1) ORDER BY a, b",
      "SELECT 0 AS a, 0 AS b UNION ALL (SELECT x AS v, -x AS `V` FROM t ORDER BY 1 DESC LIMIT 1) ORDER BY a, b",
      "SELECT 0 AS a UNION ALL (SELECT -x AS x FROM t ORDER BY x DESC LIMIT 1) ORDER BY a",
      "SELECT 0 AS a UNION ALL (SELECT -x AS x FROM t ORDER BY t.x DESC LIMIT 1) ORDER BY a",
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
      NeedsInputs(_) => fail("the positional tail uses closed Values")
    }
    assert_true(semantic(program).contains("\"take\":{\"count\":1"))
  }
}

///|
test "positional ORDER cannot resolve duplicate aliases or generated output names" {
  for receiver in ["v", "`V`", "v.member"] {
    let source = "SELECT 0 AS a, 0 AS b UNION ALL (SELECT x AS v, -x AS `V` FROM t ORDER BY " +
      receiver +
      " LIMIT 1) ORDER BY a, b"
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
  let accepted = compile(
    @query.parse_query(
      "SELECT 0 AS a UNION ALL (SELECT -x FROM t ORDER BY x DESC LIMIT 1) ORDER BY a",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  // With two input fields, the actual physical output is anonymous_2. This checks a generated field, not an unrelated misspelling.
  assert_true(
    semantic(accepted).contains("aql_set_anonymous_2"),
    msg=semantic(accepted),
  )
  for
    receiver in [
      "aql_set_anonymous_2", "`AQL_SET_ANONYMOUS_2`", "aql_set_anonymous_2.member",
    ] {
    let source = "SELECT 0 AS a UNION ALL (SELECT -x FROM t ORDER BY " +
      receiver +
      " LIMIT 1) ORDER BY a"
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
}

///|
test "ORDER and LIMIT do not grant anonymous public or named-set outputs" {
  for
    source in [
      "SELECT -x FROM t ORDER BY x LIMIT 1", "SELECT 0 AS a UNION ALL BY NAME (SELECT -x FROM t ORDER BY x LIMIT 1) ORDER BY a",
    ] {
    let actual = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    match actual {
      Err(UnsupportedProjection) => ()
      Err(UnsupportedSet) => fail(source + ": UnsupportedSet")
      Ok(program) => fail(source + ": accepted " + semantic(program))
      Err(_) => fail(source + ": another refusal")
    }
  }
}

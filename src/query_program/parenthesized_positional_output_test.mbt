///|
test "parenthesized positional windows retain the operand output context" {
  let source = "WITH r AS (SELECT 1 AS x UNION ALL SELECT 2 AS x) SELECT 0 AS a, 0 AS b UNION ALL (FROM r |> AS original |> SET x = -x |> SELECT ROW_NUMBER() OVER (ORDER BY original.x), ROW_NUMBER() OVER (ORDER BY x)) ORDER BY a, b"
  let generated = match
    compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) =>
      fail("parenthesized output lost positional context")
    Err(_) => fail("unexpected refusal")
  }
  match
    @check.check_parsed(
      generated,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the window operand uses local Values")
  }
}

///|
test "independent parenthesized window control preserves ordinal rows and types" {
  // Authored independently: expected rows (0,0), (1,2), (2,1), not a
  // serialization of frontend output. Keys and output order are explicit.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.parenthesized_windows","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1},{"x":2}]},"as":"input"},{"from":"input","analytic":{"partition_by":[],"order_by":[{"field":"x","dir":"asc","nulls":"first"}],"functions":{"up":{"fn":"row_number"}}}},{"analytic":{"partition_by":[],"order_by":[{"field":"x","dir":"desc","nulls":"last"}],"functions":{"down":{"fn":"row_number"}}}},{"select":[{"a":"up"},{"b":"down"}],"as":"right"},{"values":{"schema":{"a":{"type":"number","nullable":false},"b":{"type":"number","nullable":false}},"rows":[{"a":0,"b":0}]},"as":"left"},{"from":"left","append":{"with":"right"}},{"sort":[{"field":"a","dir":"asc","nulls":"first"},{"field":"b","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the independent control is closed")
  }
}

///|
test "positional bindings preserve double parentheses and nested set ownership" {
  // Use the existing two-row Values input to stay within this unit fixture's
  // 20-step structural budget. Public WITH coverage keeps the authored binding.
  let head = "SELECT 0 AS a, 0 AS b UNION ALL "
  for
    operand in [
      "((SELECT ROW_NUMBER() OVER (ORDER BY x), ROW_NUMBER() OVER (ORDER BY x DESC) FROM r))",
      "(SELECT ROW_NUMBER() OVER (ORDER BY x), ROW_NUMBER() OVER (ORDER BY x DESC) FROM r UNION ALL SELECT 3 AS a, 4 AS b)",
      "((SELECT SUM(x), COUNT(x) FROM r))", "(SELECT x + 10, -x FROM r)", "(WITH seed AS (SELECT x FROM r) SELECT ROW_NUMBER() OVER (ORDER BY x), ROW_NUMBER() OVER (ORDER BY x DESC) FROM seed)",
    ] {
    let program = match
      compile_query_script(
        @query.parse_query_script(
          head + operand.replace(old="FROM r", new="FROM t") + " ORDER BY a, b",
          syntax_limits(),
        ).unwrap(),
        join_order_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnsupportedProjection) => fail(operand + ": UnsupportedProjection")
      Err(_) => fail(operand + ": another refusal")
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
      NeedsInputs(_) => fail("the positional input uses local Values")
    }
  }
}

///|
test "standalone positional parentheses reach the usual checker" {
  let source = "SELECT 0 AS a, 0 AS b UNION ALL (SELECT ROW_NUMBER() OVER (ORDER BY x), ROW_NUMBER() OVER (ORDER BY x DESC) FROM t) ORDER BY a, b"
  let program = match
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(UnsupportedProjection) => fail("standalone positional context was lost")
    Err(UnsupportedCte) => fail("standalone: UnsupportedCte")
    Err(UnsupportedSet) => fail("standalone: UnsupportedSet")
    Err(UnsupportedAnalytic) => fail("standalone: UnsupportedAnalytic")
    Err(InvalidContext) => fail("standalone: InvalidContext")
    Err(Construction(issue)) => fail("standalone: " + @debug.to_string(issue))
    Err(_) => fail("unexpected standalone refusal")
  }
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the standalone control is closed")
  }
}

///|
test "positional permission never grants authored CTE or BY NAME exports" {
  let head = "WITH r AS (SELECT 1 AS x; "
  for
    source in [
      "SELECT 0 AS a UNION ALL BY NAME (SELECT ROW_NUMBER() OVER (ORDER BY x) FROM r)",
      "WITH hidden AS (SELECT ROW_NUMBER() OVER (ORDER BY x) FROM r) SELECT 0 AS a UNION ALL (SELECT * FROM hidden)",
      "WITH p AS ((SELECT ROW_NUMBER() OVER (ORDER BY x) FROM r)) FROM p |> SELECT *",
    ] {
    assert_true(
      compile_query_script(
        @query.parse_query_script(head + source, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(UnsupportedProjection),
      msg=source,
    )
  }
}

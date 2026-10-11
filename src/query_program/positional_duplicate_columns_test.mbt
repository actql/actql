///|
test "source-free left set operand keeps capture before the Values task" {
  // The installed captured DAG owns acquisition at unit zero. Ordinal left
  // and right operands still determine append order, not stage placement.
  let source = "SELECT 0 AS a, 0 AS b UNION ALL SELECT amount AS x, amount + 1 AS x FROM orders WHERE amount > 0 ORDER BY a, b"
  let context = { ..fixture_context(), captured_stage: Some("capture"), }
  let actual = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  assert_eq(@program.stages(actual).map(stage => stage.id), [
    "capture", "aql_set_seed_0", "aql_set_term_0", "aql_set_term_1", "aql_set_aligned_0",
    "aql_set_merge_0", "main",
  ])
  let wire = semantic(actual)
  assert_true(
    wire.contains(
      "\"filter\":{\"gt\":[{\"field\":\"amount\"},{\"literal\":0}]}",
    ),
  )
  assert_true(wire.contains("\"append\":{\"with\":\"r\"}"))
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("captured input keeps its existing declaration")
  }
}

///|
test "the ordinary positional JSON public control admits its Values source" {
  // The independent public control publishes the same typed NULL rows as the
  // source fixture. A Values generator requires an explicit logical producer.
  let control = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.positional_duplicates","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"a":{"type":"number","nullable":false},"b":{"type":"number","nullable":true}},"rows":[{"a":0,"b":0},{"a":1,"b":null}]},"as":"seed"},{"from":"seed","sort":[{"field":"a","dir":"asc","nulls":"first"},{"field":"b","dir":"asc","nulls":"last"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(control, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the independent Values control has no acquisition")
  }
}

///|
test "public Text routing retains scoped and empty positional DATA controls" {
  let context = { ..fixture_context(), inputs: [], }
  for
    source in [
      "DATA n = SELECT 1 AS x; FROM n |> SELECT 0 AS a, 0 AS b |> UNION ALL (FROM n AS original |> SET x = x + 1 |> SELECT original.x AS x, x AS `X`) |> ORDER BY a, b",
      "DATA e = SELECT 0 AS a, CAST(NULL AS FLOAT64) AS b WHERE FALSE UNION ALL SELECT 1 AS x, CAST(NULL AS FLOAT64) AS x WHERE FALSE; FROM e |> ORDER BY a, b",
    ] {
    let lowered = @frontend.lower(source, Text, Some(context)).unwrap()
    let program = @program.parse(
      lowered.document,
      construction_limits().program,
      format=Json,
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) =>
        fail("public positional DATA controls need no acquisition")
    }
    assert_true(
      @frontend.lower(source, Sql, Some(context)) is Err(WrongQueryForm),
    )
  }
}

///|
test "terminal positional operands keep duplicate authored aliases by position" {
  // The right operand's names are not the Result names. Both positions must
  // survive: the independently expected rows are (0,0) and (1,2).
  for
    source in [
      "SELECT 0 AS a, 0 AS b UNION ALL SELECT 1 AS x, 2 AS x ORDER BY a, b", "DATA n = SELECT 1 AS x; SELECT 0 AS a, 0 AS b UNION ALL SELECT x, x + 1 AS x FROM n ORDER BY a, b",
      "DATA n = SELECT 1 AS x; SELECT 0 AS a, 0 AS b UNION ALL SELECT x, x FROM n ORDER BY a, b",
      "DATA n = SELECT 1 AS x; SELECT 0 AS a, 0 AS b UNION ALL SELECT x, * FROM n ORDER BY a, b",
      "DATA n = SELECT 1 AS x; FROM n |> SELECT 0 AS a, 0 AS b |> UNION ALL (FROM n AS original |> SET x = x + 1 |> SELECT original.x AS x, x AS `X`) |> ORDER BY a, b",
    ] {
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    let program = match
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Ok(program) => program
      Err(DuplicateOutput) => fail("positional operand: DuplicateOutput")
      Err(_) => fail("positional operand: another rejection")
    }
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("source-free set needs no acquisition")
    }
  }
}

///|
test "positional duplicate projection preserves an independently authored complete Program" {
  // Two authored alias occurrences reserve physical indices two and three.
  // The ordinary select fields are unique before the existing alignment
  // replaces the right terminal projection names. Values/expressions are neither dropped nor
  // reevaluated, and the internal unit column never becomes a public field.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_2"},{"from":"aql_script_seed_2","derive":{"aql_query_expr_0":{"literal":0},"aql_query_expr_1":{"literal":0}}},{"select":[{"a":"aql_query_expr_0"},{"b":"aql_query_expr_1"}],"as":"aql_data_set_term_1"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_4"},{"from":"aql_script_seed_4","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":2}}},{"select":[{"a":"aql_query_expr_0"},{"b":"aql_query_expr_1"}],"as":"aql_data_set_term_3"},{"from":"aql_data_set_term_1","append":{"with":"aql_data_set_term_3"},"as":"aql_data_0"},{"from":"aql_data_0","select":["a","b"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile_data_set(
    "DATA e = SELECT 0 AS a, 0 AS b UNION ALL SELECT 1 AS x, 2 AS x; FROM e |> SELECT a, b",
  )
  assert_eq(semantic(actual), semantic(expected))
  for program in [expected, actual] {
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) =>
        fail("the independently authored Values Program is closed")
    }
  }
}

///|
test "public and name-matched duplicate columns remain rejected" {
  for
    source in [
      "SELECT 1 AS x, 2 AS x", "SELECT 0 AS a, 0 AS a UNION ALL SELECT 1 AS x, 2 AS y",
      "SELECT 0 AS a, 0 AS b UNION ALL BY NAME SELECT 1 AS a, 2 AS a",
    ] {
    assert_true(
      compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(DuplicateOutput),
      msg=source,
    )
  }
}

///|
test "source-free positional ORDER rejects an ambiguous authored alias" {
  // Positional outputs retain both values. An ORDER receiver must still
  // identify one authored alias; it cannot select either duplicate occurrence.
  let source = "SELECT 0 AS a, 0 AS b UNION ALL (SELECT 1 AS x, 2 AS x ORDER BY x)"
  let actual = compile_query_script(
    @query.parse_query_script(source, syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  )
  assert_true(
    actual is Err(AmbiguousColumn),
    msg=match actual {
      Ok(_) => "duplicate ORDER alias was accepted"
      Err(UnknownColumn) => "duplicate ORDER alias became UnknownColumn"
      Err(DuplicateOutput) => "duplicate ORDER alias became DuplicateOutput"
      Err(UnsupportedOrdering) =>
        "duplicate ORDER alias became UnsupportedOrdering"
      Err(Expression(_)) => "duplicate ORDER alias became Expression"
      Err(ExpressionTyping(_)) =>
        "duplicate ORDER alias became ExpressionTyping"
      Err(Construction(_)) => "duplicate ORDER alias became Construction"
      Err(Admission(_)) => "duplicate ORDER alias became Admission"
      _ => "unexpected duplicate ORDER alias diagnostic"
    },
  )
}

///|
test "ordinary SQL set assembly preserves duplicate positional columns" {
  let program = compile(
    @query.parse_query(
      "SELECT 0 AS a, 0 AS b UNION ALL SELECT 1 AS x, 2 AS `X` ORDER BY a, b",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("ordinary source-free operands remain closed")
  }
}

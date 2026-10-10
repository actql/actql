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
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_2"},{"from":"aql_script_seed_2","derive":{"aql_query_expr_0":{"literal":0},"aql_query_expr_1":{"literal":0}}},{"select":[{"a":"aql_query_expr_0"},{"b":"aql_query_expr_1"}],"as":"aql_data_set_term_1"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_4"},{"from":"aql_script_seed_4","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":2}}},{"select":[{"aql_set_duplicate_2":"aql_query_expr_0"},{"aql_set_duplicate_3":"aql_query_expr_1"}],"as":"aql_data_set_term_3"},{"from":"aql_data_set_term_3","select":[{"a":"aql_set_duplicate_2"},{"b":"aql_set_duplicate_3"}],"as":"aql_data_set_aligned_5"},{"from":"aql_data_set_term_1","append":{"with":"aql_data_set_aligned_5"},"as":"aql_data_set_combined_6"},{"from":"aql_data_set_combined_6","select":["a","b"],"as":"aql_data_0"},{"from":"aql_data_0","select":["a","b"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["a","b"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
      "SELECT 0 AS a, 0 AS b UNION ALL BY NAME SELECT 1 AS a, 2 AS a", "SELECT 0 AS a, 0 AS b UNION ALL (SELECT 1 AS x, 2 AS x ORDER BY x)",
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

///|
test "DATA positional right operands retain anonymous scalar values" {
  // Source-free operands each produce one row. The independently expected
  // result is [{id:10},{id:11}], with one nonnullable numeric column.
  for
    text in [
      "DATA e = SELECT 10 AS id UNION ALL SELECT 11 AS other; FROM e |> SELECT id",
      "DATA e = SELECT 10 AS id UNION ALL SELECT 11; FROM e |> SELECT id",
    ] {
    let script = @query.parse_query_script(text, syntax_limits()).unwrap()
    let program = match
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnsupportedProjection) => fail(text + ": UnsupportedProjection")
      Err(_) => fail(text + ": another lowering rejection")
    }
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("source-free DATA adds no acquisition")
    }
    assert_eq(@program.stage_count(program), 1)
    assert_true(semantic(program).contains("\"fields\":[\"id\"]"))
  }
}

///|
test "DATA positional operands preserve their independently authored Program" {
  // This expected Program is authored from source-free Values, derive,
  // ordinal alignment and append contracts. Source-free visible fields and
  // prior selected names are empty, so the private-name counter starts at zero.
  // Public values, names, types and ordering do not depend on that counter.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_2"},{"from":"aql_script_seed_2","derive":{"aql_query_expr_0":{"literal":10}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_data_set_term_1"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_4"},{"from":"aql_script_seed_4","derive":{"aql_query_expr_0":{"literal":11}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_data_set_term_3"},{"from":"aql_data_set_term_1","append":{"with":"aql_data_set_term_3"},"as":"aql_data_0"},{"from":"aql_data_0","select":["id"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile_with_set(
    "DATA e = SELECT 10 AS id UNION ALL SELECT 11; FROM e |> SELECT id",
  )
  assert_eq(semantic(actual), semantic(expected))
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("independent Values control is closed")
  }
}

///|
test "DATA positional names remain private and do not satisfy BY NAME" {
  let by_name = "DATA e = SELECT 1 AS id UNION ALL BY NAME SELECT 2; FROM e |> SELECT id"
  assert_true(
    compile_query_script(
      @query.parse_query_script(by_name, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(UnsupportedProjection),
  )
  let private_name = "DATA e = SELECT 1 AS id UNION ALL SELECT 2; FROM e |> WHERE aql_set_anonymous_0 > 0 |> SELECT id"
  assert_true(
    compile_query_script(
      @query.parse_query_script(private_name, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

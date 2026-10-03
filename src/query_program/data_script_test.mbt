///|
test "DATA producer reuse preserves explicit prefix and terminal Result owners" {
  // Authored independently from the existing DATA and RESULT contracts:
  // one producer and one stage; original retains its prefix, while active
  // names the final filtered result. DATA itself adds no exported result.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":2}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_data_0"},{"from":"aql_data_0","select":["id"],"as":"aql_result_checkpoint_0"},{"filter":{"gt":[{"field":"id"},{"literal":0}]}},{"select":["id"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id"]},"aql_retained_result_0":{"from":"aql_result_checkpoint_0","fields":["id"]}}}],"results":{"original":{"from":{"stage":"main","result":"aql_retained_result_0"}},"active":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let script = @query.parse_query_script(
    "DATA n = SELECT 2 AS id; FROM n |> RESULT original |> WHERE id > 0 |> RESULT active",
    syntax_limits(),
  ).unwrap()
  let program = compile_query_script(
    script,
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
  assert_eq(@program.stage_count(program), 1)
  assert_eq(@program.export_count(program), 2)
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("DATA does not introduce an acquisition")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "DATA binding does not discard illegal nested Result declarations" {
  let nested = @query.parse_query_script(
    "DATA n = SELECT 2 AS id |> RESULT hidden; FROM n |> SELECT id",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile_query_script(
      nested,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(UnsupportedResult),
  )
  let script = @query.parse_query_script(
    "DATA n = SELECT 2 AS id; FROM n |> RESULT saved |> WHERE id > 0 |> RESULT `SAVED`",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile_query_script(
      script,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(DuplicateOutput),
  )
}

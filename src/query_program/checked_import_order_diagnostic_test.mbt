///|
test "independent captured JOIN Program compares strict and check-only orders" {
  let program = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.checked_import_sort","stages":[{"id":"capture","inputs":{"records":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"records","filter":{"literal":true}},{"select":["id"],"as":"captured"}],"results":{"source":{"from":"captured","fields":["id"]}}},{"id":"main","inputs":{"rows":{"result":{"stage":"capture","result":"source"}}},"steps":[{"from":"rows","filter":{"eq":[{"field":"id"},{"literal":1}]},"as":"chosen"},{"from":"chosen","cross_join":{"with":"rows","max_output_rows":1000000,"select":{"left_id":"left.id","id":"right.id"}},"as":"paired"},{"select":["id"]},{"sort":{"by":[{"field":"id","direction":"asc","nulls":"first"}]},"as":"out"}],"results":{"rows":{"from":"out","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let parameters = @stage_parameters.prepare(program, {
    max_parameters: 100,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }).unwrap()
  let limits : @stage_results.LocalProgramLimits = {
    max_stages: 20,
    max_steps: 100,
    max_results: 100,
    max_work: 100000,
    max_nodes: 10000,
    max_tokens: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }
  match @stage_results.prepare_local_program(parameters, limits) {
    Ok(_) => ()
    Err(Order(stage, PipelineOrder(issue))) => fail("strict pipeline order stage \{stage}: " + @debug.to_string(issue.kind))
    Err(Order(stage, ResultOrder(issue))) => fail("strict Result order stage \{stage}: " + @debug.to_string(issue.kind))
    Err(_) => fail("strict preparation failed at another boundary")
  }
  guard @stage_results.check_local_program(parameters, limits) is Err(Order(1, PipelineOrder(issue))) else {
    fail("expected current check-only imported order gap")
  }
  assert_eq(issue.kind, @pipeline.UnresolvedOrder)
  assert_eq(@wire.cursor_path(issue.source), [Key("stages"), Index(1), Key("steps"), Index(3)])
}

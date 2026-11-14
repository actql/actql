///|
// Two independently checked tasks remain two physical occurrences. Native
// profile selection cannot collapse them to the first task or admit a Run.
test "Native source-free Values profile retains every original task" {
  let document =
    #|{"version":"actql/0.1","id":"native-multi-values-profile","stages":[{"id":"first","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}},{"id":"second","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"first":{"from":{"stage":"first","result":"rows"}},"second":{"from":{"stage":"second","result":"rows"}}}}
  let prepared = @host.prepare_effect_free_client_program(
    document,
    Json,
    preparation_environment(),
    None,
    @host.client_standard_program_preparation_limits(),
  ).unwrap()
  let graph = @host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 2)
  assert_eq(@host.prepared_client_result_count(prepared), 2)
  assert_eq(@host.prepared_client_acquisition_count(prepared), 0)
  assert_true(@strategy.graph_source_free_inputs_complete(graph))
  assert_false(@strategy.graph_program_has_effects(graph))
  assert_true(native_client_local_values_profile_supported(prepared))
}

///|
test "Native Values shape admits checked UNION graphs beyond the old 32 tasks" {
  let assets = @host.client_local_product_assets()
  guard @json.parse(assets.environment) is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    fail("packaged Environment evidence missing")
  }
  let environment = @host.admit_client_check_environment(
    assets.environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    numeric_profile_cid=Some(
      "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df",
    ),
  ).unwrap()
  let contracts = native_values_work_test_installed_contracts()
  for branches in [7, 8, 9, 17, 24] {
    let selects : Array[String] = []
    for index in 0..<branches {
      selects.push("SELECT \{index} AS v")
    }
    let context = @frontend.bind_query_context([], cid).unwrap()
    let lowered = @frontend.lower(
      "WITH t AS (" +
      selects.join(" UNION ALL ") +
      ") SELECT SUM(v) AS n FROM t",
      @frontend.Sql,
      Some(context),
    ).unwrap()
    let prepared = @host.prepare_parsed_effect_free_client_program(
      lowered.program.unwrap(),
      environment,
      None,
      @host.client_standard_program_preparation_limits(),
    ).unwrap()
    assert_eq(
      @strategy.graph_task_count(@host.prepared_client_graph(prepared)),
      4 * branches + 1,
    )
    assert_true(native_client_local_values_profile_supported(prepared))
    let requirements = @local.prepare_source_free_runtime_requirements(
      prepared,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap()
    assert_eq(requirements.maximum_limits().attempts, 4 * branches + 1)
    assert_true(requirements.finalization_round_limit(prepared).unwrap() > 0)
  }
}

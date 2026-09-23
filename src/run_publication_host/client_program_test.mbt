///|
test "ordinary values document prepares one named Effect-free result" {
  let environment = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      ),
    ),
    "sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, max_members: 10, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"client-values","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}}}}
  let input : @syntax.Limits = {
    source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
    tree: {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
    max_stages: 2,
  }
  let limits : ClientProgramPreparationLimits = {
    checking: {
      input,
      compilation: {
        work: 10000000,
        artifacts: { bytes: 10000000, nodes: 1000000, depth: 100, },
        structure: {
          stages: 2,
          steps: 10,
          results: 10,
          parameters: 1,
          bindings: 100,
          slots: 1000,
          references: 1000,
          requirements: 1000,
          tokens: 10000,
        },
        traversal: {
          nodes: 100000,
          depth: 100,
          text_bytes: 10000000,
          string_bytes: 100000,
          name_bytes: 1000000,
          pointer_units: 1000000,
          comparison_pairs: 1000000,
        },
        values: { nodes: 1000000, depth: 100, text_bytes: 100000, },
        policy: { bytes: 10000, nodes: 1000000, depth: 100, },
        patterns: { bytes: 1000000, nodes: 1000000, depth: 100, },
      },
    },
    lowering: {
      max_nodes: 100,
      max_references: 100,
      max_work: 100000,
      max_identifier_bytes: 10000,
    },
    max_parameters: 10,
    max_parameter_name_bytes: 1000,
    max_tasks: 2,
    max_graph_work: 10000,
  }
  let selected = @checked.checking_environment(
    environment,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let prepared = match
    prepare_effect_free_client_program(document, Json, selected, None, limits) {
    Ok(value) => value
    Err(_) => fail("ordinary values preparation failed")
  }
  assert_eq(prepared_client_result_count(prepared), 1)
  assert_eq(prepared_client_result_name(prepared, 0), Some("answer"))
  assert_eq(@strategy.graph_task_count(prepared_client_graph(prepared)), 1)
  let ledger = @resources.create_ledger({
    planning_work: 10000,
    attempts: 2,
    holdings: 2,
    transfer_bytes: 10000L,
    retained_bytes: 10000L,
    execution_bytes: 10000L,
  }).unwrap()
  let run = @strategy.open_source_free_dag(
    prepared_client_graph(prepared),
    ledger,
  ).unwrap()
  assert_eq(@strategy.captured_compute_first_task(run), 0)
  assert_eq(@strategy.next_captured_task(run), Some(0))
  assert_false(@strategy.captured_task_completed(run, 0))
  assert_true(@strategy.captured_task_target(run, 0) is Some(_))
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, }],
    1,
    100,
  ).unwrap()
  @strategy.configure_strategy_search(run, {
    max_offers: 1,
    max_strategies: 1,
    max_work: 1000,
    max_revisions: 1,
  }).unwrap()
  let offer = @strategy.prepare_task_offer(
    run,
    0,
    @connector.capability_registration_at(registry, 0).unwrap(),
    1,
    [{ work_slots: [0], milliseconds: Some(1L), }],
    { transfer_bytes: 0L, retained_bytes: 10L, execution_bytes: 1L, },
    100,
  ).unwrap()
  guard @strategy.revise_strategy(run, [offer], registry, None)
    is Ok(Selected(revision)) else {
    fail("source-free root was not selected")
  }
  let request = @host_driver.prepare_dispatch_inputs(
    @host_driver.open_dispatch_driver(run),
    0,
    revision,
    {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 100,
      max_value_bytes: 10000,
      common_fragment: None,
    },
    100,
    10000,
  ).unwrap()
  assert_eq(@connector.fixed_compute_request_input_count(request), 0)
  assert_true(
    prepare_effect_free_client_program(
      document.replace(old="actql/0.1", new="actql/9.9"),
      Json,
      selected,
      None,
      limits,
    )
    is Err(Syntax(_)),
  )
  assert_true(
    prepare_effect_free_client_program(document, Json, selected, None, {
      ..limits,
      lowering: { ..limits.lowering, max_nodes: 0, },
    })
    is Err(Lowering(_)),
  )
}

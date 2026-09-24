///|
test "ordinary AQL values root reaches the installed Local kernel" {
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
  let preparation : @publication_host.ClientProgramPreparationLimits = {
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
  let selected = @program_check.checking_environment(
    environment,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    selected,
    None,
    preparation,
  ).unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_true(
    @publication_host.prepare_client_task_sequence(
      prepared,
      1,
      registered_relation_contracts(),
      [],
      {
        max_steps: 1,
        max_rows: 1,
        max_cells: 1,
        max_bindings: 1,
        max_name_bytes: 1,
        expressions: {
          max_nodes: 1,
          max_work: 1,
          max_depth: 1,
          max_literal_nodes: 1,
          max_literal_text_bytes: 1,
        },
      },
      1,
      1,
    )
    is Err(@publication_host.MissingTask),
  )
  let setup = @client_local_host.open_source_free_local_host(
    prepared,
    @identity.stringify_value(registered_body(), 100000, 10000, 100),
    @identity.stringify_value(registered_values(), 100000, 10000, 100),
    1L, 0L, 0L, 0L,
  ).unwrap()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let ledger = @strategy.captured_dag_ledger(run)
  assert_true(
    @client_local_host.execute_source_free_values(setup, 0, 1000)
    is Err(@client_local_host.InvalidLimits),
  )
  let execution = @client_local_host.execute_source_free_values(
    setup, 16, 1000,
  ).unwrap()
  let completed = execution.completed_output()
  assert_eq(execution.rows().unwrap(), ["{\"id\":1}", "{\"id\":2}"])
  assert_true(@strategy.captured_task_completed(run, 0))
  assert_eq(@strategy.next_captured_task(run), None)
  let values : @execution.ValueLimits = {
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_depth: 20,
    max_work: 10000,
  }
  let bridge = @execution.prepare_managed_publication_bridge(
    completed,
    execution.material().unwrap(),
    100,
    values,
    100,
    10000,
  ).unwrap()
  for row in execution.rows().unwrap() {
    @execution.append_managed_publication_bridge_wire(bridge, row, {
      max_bytes: 100,
      max_nodes: 20,
      max_depth: 4,
      max_text_bytes: 100,
    }).unwrap()
  }
  let output = @execution.finish_managed_publication_bridge(bridge).unwrap()
  let definition = @publication.prepare_result_definition(
    @strategy.graph_program_definition_cid(graph),
    "answer",
  ).unwrap()
  let result = @publication_host.prepare_result_publication_export(
    output,
    @strategy.graph_result_occurrence(graph, 0).unwrap(),
    @publication.result_definition_contract(definition),
    {
      max_result_fields: 10,
      max_result_mapping_work: 100,
      max_result_order_work: 100,
      max_result_workspace_entries: 100,
      max_rows: 100,
      values,
      payload_wire: {
        max_columns: 10,
        max_order_work: 100,
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
      },
      logical_wire: {
        max_columns: 10,
        max_order_work: 100,
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
      },
      schema: {
        max_fields: 10,
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
      },
      max_batch_bytes: 64,
    },
  ).unwrap()
  let text = StringBuilder()
  while result.next().unwrap() is Some(chunk) {
    text.write_string(chunk)
  }
  text.write_string(result.finish().unwrap())
  assert_eq(text.to_string(), "[{\"id\":1},{\"id\":2}]")
  assert_eq(result.result_fields().unwrap(), ["id"])
  result.cancel()
  @execution.close_managed_publication_bridge(bridge)
  assert_true(execution.close())
  assert_true(execution.rows() is Err(@client_local_host.MissingOutput))
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
}

///|
test "native Values task installation binds the checked Run before Compute" {
  let environment_text =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
  let environment = @environment.read(
    @utf8.encode(environment_text),
    "sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, max_members: 10, },
  ).unwrap()
  let selected = @checked.checking_environment(
    environment,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let document =
    #|{"version":"actql/0.1","id":"site-values","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}}}}
  let prepared = @host.prepare_effect_free_client_program(
    document,
    Json,
    selected,
    None,
    {
      checking: {
        input: {
          source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
          tree: {
            max_nodes: 1000,
            max_depth: 100,
            max_string_bytes: 10000,
            max_total_string_bytes: 10000,
          },
          max_stages: 2,
        },
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
    },
  ).unwrap()
  let sequence_limits : @lower.SequenceLimits = {
    max_steps: 10,
    max_rows: 10,
    max_cells: 10,
    max_bindings: 10,
    max_name_bytes: 1000,
    expressions: {
      max_nodes: 100,
      max_work: 1000,
      max_depth: 10,
      max_literal_nodes: 100,
      max_literal_text_bytes: 1000,
    },
  }
  let manifests = @host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = @host.issue_prepared_client_values_compilation(
    prepared, manifests, sequence_limits, 32, 64, 100000, 10000, 100,
  ).unwrap()
  let template = @host.client_values_compilation_template(compilation)
  let plan = @host.client_values_compilation_compiled_plan(compilation)
  let prepared_invocation = @publication.seal_run_evidence_value(
    "prepared_invocation",
    "{\"version\":\"actql-prepared-invocation/0.1\"," +
    "\"invocation_template_cid\":\"" +
    @publication.run_evidence_value_identity(template) +
    "\",\"compiled_plan_cid\":\"" +
    @publication.publication_contract_identity(plan) +
    "\",\"execution_context_cid\":\"sha256:" +
    "a".repeat(64) +
    "\",\"host_policy_cid\":\"sha256:" +
    "b".repeat(64) +
    "\",\"policy_decision\":\"allow\"," +
    "\"expires_at\":\"2099-01-01T00:00:00.000Z\"}",
    100000,
    10000,
    100,
  ).unwrap()
  let authorization = @publication.seal_run_evidence_value(
    "run_authorization",
    "{\"version\":\"actql-run-authorization/0.1\"," +
    "\"prepared_invocation_cid\":\"" +
    @publication.run_evidence_value_identity(prepared_invocation) +
    "\",\"execution_context_cid\":\"sha256:" +
    "a".repeat(64) +
    "\",\"host_policy_cid\":\"sha256:" +
    "b".repeat(64) +
    "\",\"decision\":\"allowed\"}",
    100000,
    10000,
    100,
  ).unwrap()
  let admission = @host.admit_prepared_client_run_publication(
    prepared, template, prepared_invocation, authorization, plan,
  ).unwrap()
  let definition = @publication.issue_run_definition(
    admission,
    "site-values-scope",
    "site-values-run",
    "sha256:" + "c".repeat(64),
    "2026-09-25T00:00:00.000Z",
    "2027-01-01T00:00:00.000Z",
    100000,
    10000,
    100,
  ).unwrap()
  let binding = @remote.prepare_remote_input_binding("{}", 16).unwrap()
  let limits : NativeRemoteValuesTaskLimits = {
    finalization_quantum: 16,
    max_finalization_rounds: 1000,
    row_decode: {
      max_bytes: 100,
      max_nodes: 20,
      max_depth: 4,
      max_text_bytes: 100,
    },
    bridge_max_entries: 100,
    bridge_max_name_bytes: 10000,
    output: {
      output_export: {
        max_result_fields: 10,
        max_result_mapping_work: 100,
        max_result_order_work: 100,
        max_result_workspace_entries: 100,
        max_rows: 100,
        values: {
          max_nodes: 1000,
          max_text_bytes: 10000,
          max_depth: 20,
          max_work: 10000,
        },
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
      max_manifest_bytes: 10000,
      max_retained_bytes: 100000L,
    },
  }
  let registered = install_native_remote_values_task_executor(
    prepared, compilation, admission, definition, binding, "{}", "{}", 1L, 0L, 0L,
    0L, limits,
  )
  assert_true(registered is Ok(_))
  assert_true(
    install_native_remote_values_task_executor(
      prepared,
      compilation,
      admission,
      definition,
      @remote.prepare_remote_input_binding("{\"source\":1}", 32).unwrap(),
      "{}",
      "{}",
      1L,
      0L,
      0L,
      0L,
      limits,
    )
    is Err(InvalidInputBinding),
  )
  assert_true(
    install_native_remote_values_task_executor(
      prepared,
      compilation,
      admission,
      definition,
      binding,
      "{}",
      "{}",
      1L,
      0L,
      0L,
      0L,
      { ..limits, finalization_quantum: 0, },
    )
    is Err(InvalidLimits),
  )
}

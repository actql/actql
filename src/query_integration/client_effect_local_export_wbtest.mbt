///|
fn local_effect_export_fixture() -> (
  String,
  @program_check.CheckEnvironment,
  @publication_host.ClientEffectComputationLimits,
) {
  let document =
    #|{"version":"actql/0.1","id":"local-effect-export","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"value":{"type":"number","nullable":false}},"rows":[{"value":1}]},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]},"other":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}},"copy":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"other"}}}}}],"results":{"published":{"from":{"stage":"source","result":"out"}}}}
  let schema = "{\"additional_properties\":false,\"fields\":{\"Id\":{\"nullable\":false,\"type\":\"string\"},\"Name\":{\"nullable\":true,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"}"
  let schema_cid = "sha256:" + @sha.hex(@utf8.encode(schema))
  let before = "{\"connector_manifest_cid\":\"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1\",\"conversions\":[],"
  let after = "\"mapping_ref\":\"mapping:crm.account.v1\",\"minimum_approval\":\"none\",\"permission_rules\":[{\"effect_kind\":\"create\",\"permissions\":[\"scope:create\"],\"selector_class\":\"none\",\"write_fields\":[\"Name\"]}],\"primary_identity\":\"Id\",\"required_fields\":[],\"required_permissions\":[],\"resource_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"row_mapping\":{\"Name\":{\"field\":\"value\",\"null_behavior\":\"reject\"}},\"schema\":\"actql.mapping_contract/0.1\",\"target_ref\":\"connector://crm/account\",\"target_schema\":" +
    schema +
    ",\"target_schema_identity\":\"" +
    schema_cid +
    "\",\"version\":\"salesforce-v1\",\"writable_fields\":[\"Name\"]}"
  let mapping_cid = "sha256:" + @sha.hex(@utf8.encode(before + after))
  let mapping = before +
    "\"mapping_contract_cid\":\"" +
    mapping_cid +
    "\"," +
    after
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[{\"catalog_cid\":\"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd\",\"commands\":[],\"connector_id\":\"crm\",\"connector_version\":\"fixture\",\"contracts\":[],\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[]}],\"connector_manifest\":{\"connectors\":[{\"connector\":\"crm\",\"connector_id\":\"crm\",\"connector_version\":\"fixture\"}],\"version\":\"actql-connectors/0.1\"},\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{\"capacity\":{\"max_aggregate_array_items\":1000,\"max_artifact_bytes\":1000,\"max_artifact_rows\":1000,\"max_effect_items\":1000,\"max_graph_input_edges\":1000,\"max_graph_input_nodes\":1000,\"max_graph_output_rows\":1000,\"max_graph_paths\":1000,\"max_infer_items\":1000,\"max_model_input_tokens_per_item\":1000,\"max_model_request_bytes_per_item\":1000,\"max_model_total_duration_ms\":1000,\"max_nested_value_bytes\":1000,\"max_nested_value_depth\":1000,\"max_relation_output_rows\":1000,\"max_temporal_matches_per_key\":1000,\"max_temporal_output_rows\":1000,\"version\":\"actql-capacity-host-policy/0.1\"}},\"mapping_contracts\":[" +
    mapping +
    "],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let environment_cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let bundle = @environment.read(
    @utf8.encode(
      prefix + "\"evidence_bundle_cid\":\"" + environment_cid + "\"," + suffix,
    ),
    environment_cid,
    { max_bytes: 20000, max_nodes: 2000, max_depth: 100, max_members: 100, },
  ).unwrap()
  let environment = @program_check.checking_environment(
    bundle,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
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
  let limits : @publication_host.ClientEffectComputationLimits = {
    program: {
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
    },
    max_members: 2,
    max_header_work: 100,
    mapping: {
      max_bytes: 20000,
      max_nodes: 2000,
      max_depth: 100,
      max_members: 100,
    },
    max_mapping_work: 1000,
    effects: {
      max_members: 2,
      max_work: 1000,
      max_admission_nodes: 100,
      max_admission_depth: 10,
      max_admission_text_bytes: 1000,
    },
  }
  (document, environment, limits)
}

///|
fn local_effect_export_receipt(
  output : @execution.CompletedOutput,
  occurrence : @execution.ManagedResultOccurrence,
) -> (
  @execution.CompletedResultRelationExportPreparation,
  @execution.CompletedRelationExportReceipt,
) {
  let wire = row_wire_limits()
  let preparation = @execution.start_completed_result_relation_export(
    output,
    occurrence,
    {
      max_fields: 10,
      max_mapping_work: 100,
      max_order_work: 1000,
      max_workspace_entries: 20,
    },
    10,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 20, max_work: 10000, },
    wire,
    wire,
    { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    64,
  ).unwrap()
  while true {
    let (complete, _) = @execution.advance_completed_result_relation_export(
      preparation, 64,
    ).unwrap()
    if complete {
      break
    }
  }
  let stream = @execution.finish_completed_result_relation_export_preparation(
    preparation,
  ).unwrap()
  while @execution.next_completed_output_export(stream).unwrap() is Some(_) {

  }
  let (receipt, _) = @execution.finish_completed_relation_export(stream).unwrap()
  (preparation, receipt)
}

///|
test "shared local Artifact issuer rejects foreign Result export ownership" {
  let (document, environment, limits) = local_effect_export_fixture()
  let prepared = @publication_host.prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let identity = @publication_host.prepared_client_effect_identity(prepared)
  let definition_cid = @publication_host.prepared_client_effect_computation_definition_cid(
    prepared,
  )
  let template = native_publication_evidence(
    "bound_invocation_template",
    "{\"version\":\"actql-bound-invocation-template/0.1\",\"program_definition_cid\":\"" +
    definition_cid +
    "\",\"parameter_values_cid\":\"" +
    identity.parameter_values_cid +
    "\",\"invocation_bindings_cid\":\"" +
    native_publication_cid("effect-bindings") +
    "\",\"check_environment_cid\":\"" +
    @publication_host.prepared_client_effect_computation_environment_cid(
      prepared,
    ) +
    "\",\"grammar_manifest_cid\":\"" +
    native_publication_cid("effect-grammar") +
    "\",\"required_profile_contracts\":[],\"barrier_contract_manifest_cid\":\"" +
    native_publication_cid("effect-barriers") +
    "\",\"source_evidence\":\"unbound\"}",
  )
  let plan = native_publication_contract(
    "compiled_plan",
    "{\"version\":\"actql-compiled-plan/0.1\",\"compiler_version\":\"compiler-0.1\",\"aoa_ir_version\":\"aoa-ir-0.1\",\"executable_plan_cid\":\"" +
    native_publication_cid("effect-executable") +
    "\",\"program_definition_cid\":\"" +
    definition_cid +
    "\",\"program_semantics_cid\":\"" +
    @publication_host.prepared_client_effect_computation_semantics_cid(prepared) +
    "\",\"aoa_contract_cid\":\"" +
    native_publication_cid("effect-aoa-contract") +
    "\",\"aoa_logical_cid\":\"" +
    native_publication_cid("effect-aoa-logical") +
    "\"}",
  )
  let execution_context = native_publication_cid("effect-execution")
  let host_policy = native_publication_cid("effect-host-policy")
  let invocation = native_publication_evidence(
    "prepared_invocation",
    "{\"version\":\"actql-prepared-invocation/0.1\",\"invocation_template_cid\":\"" +
    @publication.run_evidence_value_identity(template) +
    "\",\"compiled_plan_cid\":\"" +
    @publication.publication_contract_identity(plan) +
    "\",\"execution_context_cid\":\"" +
    execution_context +
    "\",\"host_policy_cid\":\"" +
    host_policy +
    "\",\"policy_decision\":\"allow\",\"expires_at\":\"2027-01-01T00:00:00.000Z\"}",
  )
  let authorization = native_publication_evidence(
    "run_authorization",
    "{\"version\":\"actql-run-authorization/0.1\",\"prepared_invocation_cid\":\"" +
    @publication.run_evidence_value_identity(invocation) +
    "\",\"execution_context_cid\":\"" +
    execution_context +
    "\",\"host_policy_cid\":\"" +
    host_policy +
    "\",\"decision\":\"allowed\"}",
  )
  let admission = @publication_host.admit_prepared_client_effect_run_publication(
    prepared, template, invocation, authorization, plan,
  ).unwrap()
  let run_definition = @publication.issue_run_definition(
    admission,
    "scope",
    "local-effect-export",
    native_publication_cid("effect-inputs"),
    "2026-09-25T00:00:00.000Z",
    "2027-01-01T00:00:00.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let bound = @publication_host.bind_prepared_client_effect_run(
    prepared, admission, run_definition,
  ).unwrap()
  let effect_run = @publication_host.open_prepared_source_free_client_effect_run(
    bound,
    {
      planning_work: 100000,
      attempts: 10,
      holdings: 10,
      transfer_bytes: 500000L,
      retained_bytes: 200000000L,
      execution_bytes: 268435456L,
    },
  ).unwrap()
  let run = @strategy.captured_effect_run_dag(effect_run)
  let registry = search_registry()
  let dispatch = dispatch_test_limits()
  let generated = @publication_host.prepare_client_effect_task_sequence(
    prepared,
    0,
    registered_relation_contracts(),
    [],
    {
      max_steps: 100,
      max_rows: 100,
      max_cells: 10000,
      max_bindings: 100,
      max_name_bytes: 10000,
      expressions: {
        max_nodes: 10000,
        max_work: 100000,
        max_depth: 100,
        max_literal_nodes: 10000,
        max_literal_text_bytes: 10000,
      },
    },
    100000,
    10000,
  ).unwrap()
  let modules = @builtin.configure_compute_modules(
    @host_driver.open_dispatch_driver(run),
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_local=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences: [generated],
          managed_providers: [],
          managed_capacity: dispatch.capacity,
          execution: dispatch.local_execution,
          measurement: dispatch.guards,
          max_work: dispatch.candidate_work,
        },
        _ => @strategy.RunIssue::ForeignCandidate,
        _ => @strategy.RunIssue::ForeignCandidate,
      ),
    ),
  ).unwrap()
  let installed = @builtin.configured_local_module(modules).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: dispatch.local_execution.rows.input_values,
      wire: retained_attempt_wire_limits(),
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 64,
    },
    None,
  ).unwrap()
  let available = Ref(true)
  let (operations, completed) = run_local_managed_test_task(
    installed,
    run,
    0,
    [],
    [],
    1,
    available,
  )
  assert_true(
    @strategy.pin_captured_effect_sources(effect_run, 2, max_dependency_work=0)
    is Err(@strategy.PreviewWorkLimit),
  )
  let inputs = @strategy.pin_captured_effect_sources(
    effect_run,
    2,
    max_dependency_depth=0,
  ).unwrap()
  assert_eq(@strategy.captured_effect_local_result_count(inputs), 2)
  let local_result = @strategy.captured_effect_local_result_at(inputs, 0).unwrap()
  assert_eq(@strategy.captured_effect_local_result_stage(local_result), 0)
  assert_true(
    @strategy.captured_any_result_borrow_available(
      @strategy.captured_effect_local_result_borrow(local_result),
    ),
  )
  let out = @strategy.captured_effect_input_at(inputs, 0).unwrap()
  let other = @strategy.captured_effect_input_at(inputs, 1).unwrap()
  assert_true(
    @execution.managed_result_occurrence_name(
      @strategy.captured_effect_input_occurrence(out),
    ) !=
    @execution.managed_result_occurrence_name(
      @strategy.captured_effect_input_occurrence(other),
    ),
  )
  let bridge = @execution.prepare_managed_publication_bridge(
    completed,
    (operations.material)().unwrap(),
    100,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 20, max_work: 10000, },
    100,
    10000,
  ).unwrap()
  for row in local_managed_test_rows(operations) {
    @execution.append_managed_publication_bridge_wire(bridge, row, {
      max_bytes: 100,
      max_nodes: 20,
      max_depth: 4,
      max_text_bytes: 100,
    }).unwrap()
  }
  let output = @execution.finish_managed_publication_bridge(bridge).unwrap()
  let (out_preparation, out_receipt) = local_effect_export_receipt(
    output,
    @strategy.captured_effect_input_occurrence(out),
  )
  let (other_preparation, other_receipt) = local_effect_export_receipt(
    output,
    @strategy.captured_effect_input_occurrence(other),
  )
  let (second_preparation, second_receipt) = local_effect_export_receipt(
    output,
    @strategy.captured_effect_input_occurrence(out),
  )
  let mut out_index = -1
  for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
    let result = @strategy.captured_effect_local_result_at(inputs, index).unwrap()
    let occurrence = @strategy.captured_any_result_borrow_occurrence(
      @strategy.captured_effect_local_result_borrow(result),
    )
    if @execution.managed_result_occurrence_name(occurrence) == "out" {
      out_index = index
    }
  }
  assert_true(out_index >= 0)
  let dependency_export = @strategy.bind_captured_effect_local_result_managed_export(
    inputs, out_index, completed, bridge, out_preparation,
  ).unwrap()
  assert_true(
    @strategy.captured_effect_local_result_export_matches_receipt(
      inputs, dependency_export, out_receipt,
    ),
  )
  assert_false(
    @strategy.captured_effect_local_result_export_matches_receipt(
      inputs, dependency_export, other_receipt,
    ),
  )
  assert_false(
    @strategy.captured_effect_local_result_export_matches_receipt(
      inputs, dependency_export, second_receipt,
    ),
  )
  assert_true(
    @strategy.bind_captured_effect_local_result_managed_export(
      inputs, out_index, completed, bridge, other_preparation,
    )
    is Err(@strategy.ForeignOutput),
  )
  let separate_pins = @strategy.pin_captured_effect_sources(effect_run, 4).unwrap()
  assert_false(
    @strategy.captured_effect_local_result_export_matches_receipt(
      separate_pins, dependency_export, out_receipt,
    ),
  )
  assert_true(@strategy.release_captured_effect_inputs(separate_pins))
  assert_eq(
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(out_receipt),
    ),
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(other_receipt),
    ),
  )
  assert_eq(
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(out_receipt),
    ),
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(second_receipt),
    ),
  )
  let local_definition = @publication_host.issue_client_effect_local_result_definition(
    prepared, 0, "out", 4096, 32, 8,
  ).unwrap()
  let local_invocation = @publication_host.issue_source_free_client_effect_local_invocation(
    prepared, 0, 4096, 32, 8,
  ).unwrap()
  let policy = native_publication_cid("effect-data-policy")
  let observation = native_publication_evidence(
    "observation_set",
    "{\"version\":\"actql-observation-set/0.1\"," +
    "\"invocation_template_cid\":\"" +
    @publication.run_evidence_value_identity(template) +
    "\",\"source_evidence_cids\":[],\"captured_input_artifact_cids\":[]," +
    "\"consistency\":\"no_external_sources\",\"capture_started_at\":null," +
    "\"capture_completed_at\":null,\"replayability\":{" +
    "\"materialized\":false,\"availability_evidence_cids\":[]}," +
    "\"data_policy_cid\":\"" +
    policy +
    "\"}",
  )
  let run_invocation = @publication.issue_run_invocation(
    template, observation, 65536, 4096, 32,
  ).unwrap()
  let retention = native_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\",\"retention_contract_cid\":\"" +
    native_publication_cid("effect-retention") +
    "\",\"effective_data_policy_cid\":\"" +
    policy +
    "\",\"available_until\":\"2026-09-25T01:00:00.000Z\",\"delete_by\":\"2026-09-25T02:00:00.000Z\",\"extension_ceiling_at\":\"2026-09-25T03:00:00.000Z\",\"metadata_retention_policy_cid\":\"" +
    native_publication_cid("effect-metadata") +
    "\",\"metadata_delete_by\":\"2026-09-25T04:00:00.000Z\",\"clock_contract_cid\":\"" +
    native_publication_cid("effect-clock") +
    "\"}",
  )
  let issue = (
    owner : @publication_host.PreparedClientEffectComputation,
    preparation : @execution.CompletedResultRelationExportPreparation,
    receipt : @execution.CompletedRelationExportReceipt,
  ) => {
    @publication_host.issue_source_free_client_effect_local_result_artifact(
      owner, inputs, 0, out, completed, bridge, preparation, local_definition, local_invocation,
      receipt, retention, admission, run_definition, run_invocation, observation,
      65536, 4096, 32,
    )
  }
  assert_true(issue(prepared, out_preparation, out_receipt) is Ok(_))
  let foreign_run_definition = @publication.issue_run_definition(
    admission,
    "scope",
    "another-local-effect-export",
    native_publication_cid("effect-inputs"),
    "2026-09-25T00:00:00.000Z",
    "2027-01-01T00:00:00.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(
    @publication_host.issue_source_free_client_effect_local_result_artifact(
      prepared, inputs, 0, out, completed, bridge, out_preparation, local_definition,
      local_invocation, out_receipt, retention, admission, foreign_run_definition,
      run_invocation, observation, 65536, 4096, 32,
    )
    is Err(@publication_host.ForeignRun),
  )
  assert_true(
    issue(prepared, out_preparation, other_receipt)
    is Err(@publication_host.ForeignExport),
  )
  assert_true(
    @publication_host.issue_source_free_client_effect_local_result_artifact(
      prepared, inputs, 0, other, completed, bridge, out_preparation, local_definition,
      local_invocation, out_receipt, retention, admission, run_definition, run_invocation,
      observation, 65536, 4096, 32,
    )
    is Err(@publication_host.ForeignExport),
  )
  assert_true(
    issue(prepared, other_preparation, other_receipt)
    is Err(@publication_host.ForeignExport),
  )
  assert_true(
    issue(prepared, out_preparation, second_receipt)
    is Err(@publication_host.ForeignExport),
  )
  let foreign = @publication_host.prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  assert_true(
    issue(foreign, out_preparation, out_receipt)
    is Err(@publication_host.ForeignOwner),
  )
  @execution.cancel_completed_relation_export_receipt(out_receipt) |> ignore
  assert_false(
    @strategy.captured_effect_local_result_export_matches_receipt(
      inputs, dependency_export, out_receipt,
    ),
  )
  assert_true(
    issue(prepared, out_preparation, out_receipt)
    is Err(@publication_host.ForeignExport),
  )
  @execution.cancel_completed_relation_export_receipt(other_receipt) |> ignore
  @execution.cancel_completed_result_relation_export(out_preparation) |> ignore
  @execution.cancel_completed_result_relation_export(other_preparation)
  |> ignore
  @execution.close_managed_publication_bridge(bridge)
  assert_true(
    issue(prepared, second_preparation, second_receipt)
    is Err(@publication_host.ForeignExport),
  )
  @execution.cancel_completed_relation_export_receipt(second_receipt) |> ignore
  @execution.cancel_completed_result_relation_export(second_preparation)
  |> ignore
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_eq(@strategy.captured_effect_local_result_count(inputs), 0)
  assert_true(@strategy.captured_effect_local_result_at(inputs, 0) is None)
  assert_false(
    @strategy.captured_any_result_borrow_available(
      @strategy.captured_effect_local_result_borrow(local_result),
    ),
  )
  available.val = false
  (operations.close)()
  (operations.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
}

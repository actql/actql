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
    1L,
    0L,
    0L,
    0L,
  ).unwrap()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let ledger = @strategy.captured_dag_ledger(run)
  assert_true(
    @client_local_host.execute_source_free_values(setup, 0, 1000)
    is Err(@client_local_host.InvalidLimits),
  )
  let execution = @client_local_host.execute_source_free_values(setup, 16, 1000).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":1}", "{\"id\":2}"])
  assert_true(@strategy.captured_task_completed(run, 0))
  assert_eq(@strategy.next_captured_task(run), None)
  let values : @execution.ValueLimits = {
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_depth: 20,
    max_work: 10000,
  }
  let row_limits : @execution.RetainedRowDecodeLimits = {
    max_bytes: 100,
    max_nodes: 20,
    max_depth: 4,
    max_text_bytes: 100,
  }
  let export_limits : @publication_host.PublicationOutputExportLimits = {
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
  }
  assert_true(
    execution.prepare_result_export(1, row_limits, 100, 10000, export_limits)
    is Err(@client_local_host.UnknownResult),
  )
  let result_owner = execution
    .prepare_result_export(0, row_limits, 100, 10000, export_limits)
    .unwrap()
  let result = result_owner.output_export()
  let text = StringBuilder()
  while result.next().unwrap() is Some(chunk) {
    text.write_string(chunk)
  }
  text.write_string(result.finish().unwrap())
  assert_eq(text.to_string(), "[{\"id\":1},{\"id\":2}]")
  assert_eq(result.result_fields().unwrap(), ["id"])
  result_owner.close()
  let site_result_owner = execution
    .prepare_result_export(0, row_limits, 100, 10000, export_limits)
    .unwrap()
  let site_budget = @remote.prepare_remote_dispatch_budget(1L, 1L).unwrap()
  let site_cid = "sha256:" + @sha.hex(@utf8.encode("source-free-site"))
  let site_request = @remote.prepare_dispatch_request(
    "source-free-coordinator",
    site_cid,
    "values_0",
    1,
    "source-free-site-budget",
    "native-site",
    1,
    site_cid,
    "local",
    "local/1",
    "strategy/1",
    site_cid,
    site_cid,
    @remote.remote_dispatch_budget_cid(site_budget),
    site_cid,
    site_cid,
  ).unwrap()
  let releases = [0]
  let site_output = @native_remote_standard.prepare_native_remote_standard_output_from_export(
    site_request,
    0,
    site_result_owner.output_export(),
    () => {
      site_result_owner.close()
      releases[0] += 1
      true
    },
    {
      output_export: export_limits,
      max_manifest_bytes: 10000,
      max_retained_bytes: 100000L,
    },
    site_budget,
  )
  assert_true(
    site_output is @native_remote_runtime.NativeRemoteExecutionFailed(_),
  )
  assert_eq(releases[0], 1)
  assert_true(execution.close())
  assert_true(execution.rows() is Err(@client_local_host.MissingOutput))
  assert_true(
    execution.prepare_result_export(0, row_limits, 100, 10000, export_limits)
    is Err(@client_local_host.LocalValuesResultExportIssue::MissingOutput),
  )
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)

  // The native harness supplies a signed runtime bundle and physical SQLite
  // journal. Other targets have already checked the Local kernel path above.
  guard @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_VALUES_ROOT")
    is Some(root_path) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(sqlite_path) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(crypto_path) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_TARGET") is Some(target) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY")
    is Some(public_key) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY")
    is Some(bundle_body) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID")
    is Some(bundle_cid) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE")
    is Some(signature) else {
    return
  }
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
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
  let compilation = @publication_host.issue_prepared_client_values_compilation(
    prepared, manifests, sequence_limits, 32, 64, 100000, 10000, 100,
  ).unwrap()
  let template = @publication_host.client_values_compilation_template(
    compilation,
  )
  let plan = @publication_host.client_values_compilation_compiled_plan(
    compilation,
  )
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
  let admission = @publication_host.admit_prepared_client_run_publication(
    prepared, template, prepared_invocation, authorization, plan,
  ).unwrap()
  let definition = @publication.issue_run_definition(
    admission,
    "native-values-scope",
    "native-values-run",
    "sha256:" + "c".repeat(64),
    "2026-09-25T00:00:00.000Z",
    "2027-01-01T00:00:00.000Z",
    100000,
    10000,
    100,
  ).unwrap()
  let definition_cid = @publication.publication_contract_identity(definition)
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    native_publication_cid("native-values-coordinator"),
    "native-values-request-1",
  ).unwrap()
  let run_binding = @publication_host.bind_source_free_client_values_run(
    prepared, compilation, admission, definition,
  ).unwrap()
  let input_binding = @remote.prepare_remote_input_binding("{}", 16).unwrap()
  let executor = @native_remote_values.install_native_remote_values_task_executor(
    prepared,
    compilation,
    admission,
    definition,
    input_binding,
    @identity.stringify_value(registered_body(), 100000, 10000, 100),
    @identity.stringify_value(registered_values(), 100000, 10000, 100),
    1L,
    0L,
    0L,
    0L,
    {
      finalization_quantum: 16,
      max_finalization_rounds: 1000,
      row_decode: row_limits,
      bridge_max_entries: 100,
      bridge_max_name_bytes: 10000,
      output: {
        output_export: export_limits,
        max_manifest_bytes: 10000,
        max_retained_bytes: 1048576L,
      },
    },
  ).unwrap()
  let sqlite = @native_sqlite.load_library(sqlite_path).unwrap()
  let crypto = @native_signature.load_library(crypto_path).unwrap()
  let root = @native_filesystem.open_root(root_path).unwrap()
  let component = b"native-runtime"
  let writer = root
    .create_writer("values-runtime-stage", component.length().to_int64())
    .unwrap()
  writer.append(component).unwrap()
  let generation = writer.seal("runtime-component").unwrap()
  let bundles = @native_runtime_bundle.open_runtime_bundle_store(
    sqlite,
    crypto,
    root_path,
    [
      {
        issuer_authority: "bundle-authority-a",
        key_id: "key-a",
        public_key_pem: public_key,
      },
    ],
    target,
    component.length().to_int64(),
    4,
    8,
    262144L,
  ).unwrap()
  bundles
  .adopt(
    "actql-remote-runtime-bundle-signature/0.1", "key-a", bundle_cid, bundle_body,
    signature, "runtime-component", generation,
  )
  .unwrap()
  |> ignore
  bundles.activate(bundle_cid).unwrap() |> ignore
  let active_runtime = bundles
    .acquire_active_component(
      "sha256:" + @sha.hex(component),
      target,
      "runtime-process:source-free-values",
    )
    .unwrap()
  let site = @site.create_site(
    "native-values-site", 1, bundle_cid, 2, 2, 1048576L, 268435456L,
  ).unwrap()
  let control = @remote.create_site_dispatch_journal(
    site, "actql-remote-site/0.1",
  ).unwrap()
  let journal = @native_remote_journal.open_journal(
    sqlite,
    root_path + "/values-journal.sqlite3",
    262144L,
    control,
  ).unwrap()
  let budget = @remote.prepare_remote_dispatch_budget(1048576L, 1048576L).unwrap()
  let operation_capability = native_publication_cid(
    "native-values-operation-capability",
  )
  let issuer_capability = native_publication_cid(
    "native-values-issuer-capability",
  )
  let runtime = @native_remote_values.open_native_remote_values_site_runtime(
    site,
    active_runtime,
    operation_capability,
    issuer_capability,
    executor,
    journal,
    bundles,
    [budget],
  ).unwrap()
  let (connector_registration, connector_revision, strategy_revision) = @native_runtime_bundle.native_active_runtime_connector_scope(
    active_runtime,
  )
  let dispatch = @publication_host.prepare_source_free_client_values_dispatch(
    run_binding,
    request,
    1,
    "native-values-dispatch-1",
    {
      site_key: "native-values-site",
      site_generation: 1,
      runtime_bundle_cid: bundle_cid,
      connector_registration,
      connector_revision,
      strategy_revision,
      obligations_cid: native_publication_cid("native-values-obligations"),
      budget_cid: @remote.remote_dispatch_budget_cid(budget),
      evidence_issuer_capability_cid: issuer_capability,
      grant_cid: operation_capability,
    },
  ).unwrap()
  assert_eq(
    @remote.dispatch_request_task_scope(dispatch),
    (
      definition_cid,
      @publication_host.client_values_compilation_plan_node_id(compilation),
    ),
  )
  assert_true(
    @remote.remote_input_binding_matches_dispatch(input_binding, dispatch),
  )
  assert_native_remote_standard_output(
    runtime, journal, dispatch, input_binding, "[{\"id\":1},{\"id\":2}]",
  )
}

///|
fn native_publication_cid(value : String) -> String {
  "sha256:" + @sha.hex(@utf8.encode(value))
}

///|
fn native_publication_contract(
  name : String,
  body : String,
) -> @publication.PublicationContract {
  @publication.seal_publication_contract(name, body, 65536, 4096, 32).unwrap()
}

///|
fn native_publication_evidence(
  name : String,
  body : String,
) -> @publication.RunEvidenceValue {
  @publication.seal_run_evidence_value(name, body, 65536, 4096, 32).unwrap()
}

///|
fn native_publication_export_limits() -> @publication_host.PublicationOutputExportLimits {
  {
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
  }
}

///|
fn prepare_native_publication_local_run() -> (
  @strategy.CapturedDAG,
  @native_host.NativeStandardStrategyRun,
  @mock.MockQueryIssuer,
) raise {
  let (run, issuer) = captured_graph_fixture()
  let registry = search_registry()
  ignore(channel_test_selection(run, registry))
  let host = @dbhost.configure_strategy_dispatch(
    run,
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    @connector.capability_registration_at(registry, 1).unwrap(),
    dispatch_test_generated(run),
    dispatch_test_limits(),
  ).unwrap()
  let runtime_owner = @native_host.open_native_standard_strategy_run(
    host,
    native_compute_import_limits(),
    100000L,
    1000000L,
  ).unwrap()
  (run, runtime_owner, issuer)
}

///|
fn prepare_native_publication_duckdb_run(
  library_path : String,
) -> (
  @strategy.CapturedDAG,
  @native_host.NativeStandardStrategyRun,
  @mock.MockQueryIssuer,
) raise {
  let (run, issuer) = captured_graph_fixture()
  let registry = search_registry()
  let registration = @connector.capability_registration_at(registry, 1).unwrap()
  @strategy.configure_strategy_search(run, {
    max_offers: 3,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 1,
  }).unwrap()
  let retention = @duckdb_compute.duckdb_task_retention_capacity(
    fixed_compute_attempt_limits(),
  ).unwrap()
  let offers = Array::makei(3, index => {
    @strategy.prepare_task_offer(
      run,
      index + 1,
      registration,
      8,
      [
        { work_slots: [0, 2, 3, 5, 6, 7], milliseconds: Some(1L), },
        { work_slots: [1, 4], milliseconds: Some(20L), },
      ],
      {
        transfer_bytes: 100000L,
        retained_bytes: retention,
        execution_bytes: 134217728L,
      },
      100,
    ).unwrap()
  })
  ignore(@strategy.revise_strategy(run, offers, registry, None).unwrap())
  let host = @dbhost.configure_strategy_dispatch(
    run,
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    registration,
    dispatch_test_generated(run),
    dispatch_test_limits(),
  ).unwrap()
  let library = @native_duckdb.load_library(library_path).unwrap()
  let runtime_owner = @native_host.open_native_standard_strategy_run(
    host,
    native_compute_import_limits(),
    100000L,
    1000000L,
    library=Some(library),
  ).unwrap()
  (run, runtime_owner, issuer)
}

///|
fn native_publication_retention(
  token : String,
  index : Int,
) -> @publication.PublicationContract {
  let suffix = index.to_string()
  native_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\"," +
    "\"retention_contract_cid\":\"" +
    native_publication_cid(token + "-retention-" + suffix) +
    "\",\"effective_data_policy_cid\":\"" +
    native_publication_cid(token + "-data-policy") +
    "\",\"available_until\":\"2026-09-21T00:00:00.000Z\"," +
    "\"delete_by\":\"2026-09-22T00:00:00.000Z\"," +
    "\"extension_ceiling_at\":\"2026-09-22T00:00:00.000Z\"," +
    "\"metadata_retention_policy_cid\":\"" +
    native_publication_cid(token + "-metadata-policy-" + suffix) +
    "\",\"metadata_delete_by\":\"2026-09-23T00:00:00.000Z\"," +
    "\"clock_contract_cid\":\"" +
    native_publication_cid(token + "-clock") +
    "\"}",
  )
}

///|
fn native_publication_run_context(
  program_cid : String,
  token : String,
) -> (
  @native_run_publication.NativeEffectFreeRunContext,
  Array[@publication.PublicationContract],
  @native_run_publication.NativeRunPublicationIntent,
  @native_run_publication.NativeRunPublicationOccurrence,
) {
  let template = native_publication_evidence(
    "bound_invocation_template",
    "{\"version\":\"actql-bound-invocation-template/0.1\"," +
    "\"program_definition_cid\":\"" +
    program_cid +
    "\",\"parameter_values_cid\":\"" +
    native_publication_cid(token + "-parameters") +
    "\",\"invocation_bindings_cid\":\"" +
    native_publication_cid(token + "-bindings") +
    "\",\"check_environment_cid\":\"" +
    native_publication_cid(token + "-environment") +
    "\",\"grammar_manifest_cid\":\"" +
    native_publication_cid(token + "-grammar") +
    "\",\"required_profile_contracts\":[]," +
    "\"barrier_contract_manifest_cid\":\"" +
    native_publication_cid(token + "-barriers") +
    "\",\"source_evidence\":\"unbound\"}",
  )
  let plan = native_publication_contract(
    "compiled_plan",
    "{\"version\":\"actql-compiled-plan/0.1\"," +
    "\"compiler_version\":\"compiler-0.1\"," +
    "\"aoa_ir_version\":\"aoa-ir-0.1\"," +
    "\"executable_plan_cid\":\"" +
    native_publication_cid(token + "-executable") +
    "\",\"program_definition_cid\":\"" +
    program_cid +
    "\",\"program_semantics_cid\":\"" +
    native_publication_cid(token + "-semantics") +
    "\",\"aoa_contract_cid\":\"" +
    native_publication_cid(token + "-aoa-contract") +
    "\",\"aoa_logical_cid\":\"" +
    native_publication_cid(token + "-aoa-logical") +
    "\"}",
  )
  let execution_context_cid = native_publication_cid(token + "-execution")
  let host_policy_cid = native_publication_cid(token + "-host-policy")
  let prepared = native_publication_evidence(
    "prepared_invocation",
    "{\"version\":\"actql-prepared-invocation/0.1\"," +
    "\"invocation_template_cid\":\"" +
    @publication.run_evidence_value_identity(template) +
    "\",\"compiled_plan_cid\":\"" +
    @publication.publication_contract_identity(plan) +
    "\",\"execution_context_cid\":\"" +
    execution_context_cid +
    "\",\"host_policy_cid\":\"" +
    host_policy_cid +
    "\",\"policy_decision\":\"allow\"," +
    "\"expires_at\":\"2026-09-21T04:00:00.000Z\"}",
  )
  let authorization = native_publication_evidence(
    "run_authorization",
    "{\"version\":\"actql-run-authorization/0.1\"," +
    "\"prepared_invocation_cid\":\"" +
    @publication.run_evidence_value_identity(prepared) +
    "\",\"execution_context_cid\":\"" +
    execution_context_cid +
    "\",\"host_policy_cid\":\"" +
    host_policy_cid +
    "\",\"decision\":\"allowed\"}",
  )
  let admission = @publication.admit_run_publication(
    template, prepared, authorization, plan,
  ).unwrap()
  let run_definition = @publication.issue_run_definition(
    admission,
    "scope",
    token + "-run",
    native_publication_cid(token + "-inputs"),
    "2026-09-20T00:00:00.000Z",
    "2026-09-21T04:00:00.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let observation = native_publication_evidence(
    "observation_set",
    "{\"version\":\"actql-observation-set/0.1\"," +
    "\"invocation_template_cid\":\"" +
    @publication.run_evidence_value_identity(template) +
    "\",\"source_evidence_cids\":[]," +
    "\"captured_input_artifact_cids\":[]," +
    "\"consistency\":\"no_external_sources\"," +
    "\"capture_started_at\":null,\"capture_completed_at\":null," +
    "\"replayability\":{\"materialized\":false," +
    "\"availability_evidence_cids\":[]},\"data_policy_cid\":\"" +
    native_publication_cid(token + "-observation-policy") +
    "\"}",
  )
  let invocation = @publication.issue_run_invocation(
    template, observation, 65536, 4096, 32,
  ).unwrap()
  let normalization_journal = native_publication_evidence(
    "normalization_journal",
    "{\"version\":\"actql-normalization-journal/0.1\"," +
    "\"rule_catalog_cid\":\"" +
    native_publication_cid(token + "-rules") +
    "\",\"entries\":[]}",
  )
  let authoring = native_publication_evidence(
    "authoring_context",
    "{\"version\":\"actql-authoring-context/0.1\"," +
    "\"program_definition_cid\":\"" +
    program_cid +
    "\",\"annotations\":[]}",
  )
  let authority_scope_cid = native_publication_cid(token + "-authority")
  (
    {
      admission,
      run_definition,
      invocation,
      observation,
      normalization_journal,
      binding_names: [],
      binding_digests: [],
      source_evidence: [],
      model_evidence: [],
      barrier_attempt_receipt_cids: [],
      source_advances: [],
      authoring,
    },
    [
      native_publication_retention(token, 0),
      native_publication_retention(token, 1),
    ],
    {
      tenant_id: "tenant",
      authority_scope_cid,
      publication_policy_cid: native_publication_cid(token + "-policy"),
      publication_target_cid: native_publication_cid(token + "-target"),
      requested_at: "2026-09-20T00:00:00.000Z",
    },
    {
      attempt_id: token + "-attempt",
      fence_cid: native_publication_cid(token + "-fence"),
      external_idempotency_key: None,
      started_at: "2026-09-20T00:00:01.000Z",
      committed_at: "2026-09-20T00:00:02.000Z",
    },
  )
}

///|
fn consume_native_publication_result(
  session : @native_result_access.NativeResultAccessSession,
) -> String {
  let output : Array[Byte] = []
  while true {
    let chunk = session.next(3).unwrap()
    for byte in chunk.bytes {
      output.push(byte)
    }
    if chunk.bytes.length() > 0 {
      ignore(session.confirm_chunk().unwrap())
    }
    if chunk.eof {
      break
    }
  }
  ignore(session.confirm_sink_finished().unwrap())
  @utf8.decode_lossy(Bytes::from_array(output))
}

///|
test "native standard Host exposes each checked task completion once" {
  let (captured, runtime_owner, query_issuer) = prepare_native_publication_local_run()
  for expected_task in [1, 2, 3] {
    let completion = @native_host.execute_next_native_standard_strategy_task(
        runtime_owner,
      )
      .unwrap()
      .unwrap()
    assert_eq(completion.task, expected_task)
    let target = @strategy.captured_task_target(captured, expected_task).unwrap()
    let recorded = @strategy.captured_task_output(
      captured, expected_task, target,
    ).unwrap()
    assert_true(
      @execution.completed_output_matches_port(
        completion.output,
        @strategy.graph_task_owner(
          @strategy.captured_dag_graph(captured),
          expected_task,
        ).unwrap(),
        target,
      ),
    )
    assert_eq(
      @execution.completed_row_count(completion.output),
      @execution.completed_row_count(recorded),
    )
  }
  assert_true(
    @native_host.execute_next_native_standard_strategy_task(runtime_owner)
    is Ok(None),
  )
  assert_true(
    @native_host.execute_next_native_standard_strategy_task(runtime_owner)
    is Err(Closed),
  )
  assert_true(@native_host.native_standard_strategy_run_complete(runtime_owner))
  @mock.close_mock_query_issuer(query_issuer)
  assert_true(
    @native_host.close_native_standard_strategy_run(runtime_owner).unwrap(),
  )
  let graph = @strategy.captured_dag_graph(captured)
  for task = @strategy.graph_task_count(graph) - 1; task > 0; task = task - 1 {
    @strategy.close_captured_task_output(captured, task)
  }
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(captured))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
}

///|
fn verify_native_publication_run(
  run : @strategy.CapturedDAG,
  token : String,
  sqlite_library_path : String,
  root : String,
  strategy_runtime_owner : @native_host.NativeStandardStrategyRun,
  query_issuer : @mock.MockQueryIssuer,
  expected_runtime_tasks : Int,
) -> Unit raise {
  let graph = @strategy.captured_dag_graph(run)
  let (run_context, retentions, intent, occurrence) = native_publication_run_context(
    @strategy.graph_program_definition_cid(graph),
    token,
  )
  let authority = native_publication_cid(token + "-store")
  let library = @native_sqlite.load_library(sqlite_library_path).unwrap()
  let store = @native_publication_store.open_store(
    library, root, authority, 1048576L, 16L, 65536L,
  ).unwrap()
  let publication_authority = @native_run_publication.install_native_run_publication_authority(fn(
      _,
    ) {
      true
    },
  )
  let service = @native_run_publication.install_native_run_publication_service(
    store, publication_authority, 65536, 4096, 32,
  ).unwrap()
  let result_contexts : Array[
    @native_run_publication.NativeCapturedResultPublicationContext,
  ] = Array::makei(@strategy.graph_result_count(graph), index => {
    retention: retentions[index],
    computation_contract_cid: native_publication_cid(
      token + "-compute-" + index.to_string(),
    ),
    input_relation_cids: [],
    scope_cid: native_publication_cid(token + "-scope-" + index.to_string()),
    effective_data_policy_cid: native_publication_cid(token + "-data-policy"),
    store_authority_cid: authority,
    material_generation_cid: native_publication_cid(
      token + "-material-" + index.to_string(),
    ),
    max_payload_bytes: 10000L,
  })
  let committed = match
    @native_host.execute_and_publish_native_standard_strategy_run(
      strategy_runtime_owner,
      service,
      run_context,
      result_contexts,
      intent,
      occurrence,
      native_publication_export_limits(),
    ) {
    Ok(value) => value
    Err(@native_host.Strategy(_)) => abort("standard strategy failure")
    Err(@native_host.Preparation(_)) => abort("publication preparation failure")
    Err(@native_host.Publication(_, _)) => abort("publication commit failure")
  }
  assert_true(committed.committed)
  assert_true(
    @native_host.native_standard_strategy_run_complete(strategy_runtime_owner),
  )
  assert_eq(
    @native_host.native_standard_strategy_run_task_count(strategy_runtime_owner),
    expected_runtime_tasks,
  )
  @mock.close_mock_query_issuer(query_issuer)
  assert_true(store.close().unwrap())
  let reopened = @native_publication_store.open_store(
    library, root, authority, 1048576L, 16L, 65536L,
  ).unwrap()
  for name in ["b", "c"] {
    let resolved = reopened
      .resolve_committed_result(
        intent.tenant_id,
        intent.authority_scope_cid,
        @publication.publication_contract_identity(run_context.run_definition),
        name,
        65536,
        4096,
        32,
      )
      .unwrap()
      .unwrap()
    assert_eq(resolved.read.result_name, name)
    assert_true(resolved.read.byte_count > 1L)
    assert_true(resolved.read.row_count > 0L)
  }
  let access_authority = @native_result_access.install_native_result_access_authority(
    request => request.principal_id == "principal",
    _ => {
      Some({
        authorization_context_cid: native_publication_cid(
          token + "-read-authorization",
        ),
        data_ceiling_cid: native_publication_cid(token + "-read-ceiling"),
        egress_admission_cid: native_publication_cid(token + "-read-egress"),
        expires_at: "2026-09-21T00:00:00.000Z",
        max_bytes: 1000,
        max_uses: 1,
      })
    },
    authorization => {
      authorization.request.principal_id == "principal" &&
      (authorization.stage == "read" || authorization.stage == "receipt")
    },
  )
  let access = @native_result_access.install_native_result_access_service(
    reopened,
    access_authority,
    () => "2026-09-20T01:00:00.000Z",
    65536,
    4096,
    32,
    65536,
    3,
  ).unwrap()
  for
    (format, expected, attempt_suffix) in [
      ("json", "[{\"id\":3}]", "json"),
      ("jsonl", "{\"id\":3}\n", "jsonl"),
      ("csv", "\"id\"\n3\n", "csv"),
    ] {
    let session = @native_result_access.open_native_result_access(access, {
      tenant_id: intent.tenant_id,
      authority_scope_cid: intent.authority_scope_cid,
      run_definition_cid: @publication.publication_contract_identity(
        run_context.run_definition,
      ),
      principal_id: "principal",
      purpose: "download",
      result_name: "c",
      format,
      attempt_id: token + "-delivery-" + attempt_suffix,
    }).unwrap()
    assert_eq(consume_native_publication_result(session), expected)
  }
  assert_true(reopened.close().unwrap())
  assert_true(
    @native_host.close_native_standard_strategy_run(strategy_runtime_owner).unwrap(),
  )
  for task = @strategy.graph_task_count(graph) - 1; task > 0; task = task - 1 {
    @strategy.close_captured_task_output(run, task)
  }
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
}

///|
test "standard Local output reaches the durable native publication commit" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_library_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(root) else {
    return
  }
  let token = "local-publication-" + @env.now().to_string()
  let (run, runtime_owner, query_issuer) = prepare_native_publication_local_run()
  verify_native_publication_run(
    run, token, sqlite_library_path, root, runtime_owner, query_issuer, 0,
  )
}

///|
test "standard DuckDB output reaches the durable native publication commit" {
  guard @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY")
    is Some(duckdb_library_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_library_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(root) else {
    return
  }
  let token = "duckdb-publication-" + @env.now().to_string()
  let (run, runtime_owner, query_issuer) = prepare_native_publication_duckdb_run(
    duckdb_library_path,
  )
  verify_native_publication_run(
    run, token, sqlite_library_path, root, runtime_owner, query_issuer, 3,
  )
}

///|
fn assert_native_remote_standard_output(
  runtime : @native_remote_runtime.NativeRemoteRuntime,
  journal : @native_remote_journal.Journal,
  request : @remote.DispatchRequest,
  input_binding : @remote.RemoteInputBinding,
  expected : String,
) -> Unit raise {
  let operation = @remote.admit_remote_poll_operation_json(
    @remote.remote_poll_dispatch_json(request, input_binding).unwrap(),
  ).unwrap()
  let acknowledge_acceptance = fn(request) {
    let (_, record) = journal.accept(request).unwrap()
    Ok(record)
  }
  let acknowledge_status = fn(request) {
    let observed = journal.observation(request).unwrap()
    Ok(Some(@native_remote_journal.recovered_site_dispatch_record(observed)))
  }
  guard @native_remote_agent.advance_native_outbound_operation(
      runtime,
      Some(operation),
      acknowledge_acceptance,
      acknowledge_status,
    )
    is Ok(@native_remote_agent.DispatchObserved(identity, _)) else {
    fail("standard remote dispatch was not observed")
  }
  assert_eq(identity, @remote.dispatch_request_identity(request))
  let observed = journal.observation(request).unwrap()
  let subject = @native_remote_journal.recovered_site_dispatch_subject(observed).unwrap()
  let material_generation = @remote.remote_managed_output_subject_projection(
      subject,
    )[1]
  let reader = runtime
    .open_output_reader(request, material_generation, 7)
    .unwrap()
  let bytes : Array[Byte] = []
  while true {
    let chunk = reader.next().unwrap()
    for byte in chunk.bytes {
      bytes.push(byte)
    }
    if chunk.eof {
      break
    }
  }
  assert_eq(@utf8.decode_lossy(Bytes::from_array(bytes)), expected)
  assert_true(reader.finish().unwrap())
  let release = @remote.admit_remote_poll_operation_json(
    @remote.remote_poll_release_json(request).unwrap(),
  ).unwrap()
  guard @native_remote_agent.advance_native_outbound_operation(
      runtime,
      Some(release),
      acknowledge_acceptance,
      acknowledge_status,
    )
    is Ok(@native_remote_agent.ReleaseObserved(released_identity, _)) else {
    fail("standard remote output release was not observed")
  }
  assert_eq(released_identity, @remote.dispatch_request_identity(request))
}

///|
test "native Remote Site executes registered Local and DuckDB tasks" {
  guard @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY") is Some(duckdb_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY")
    is Some(crypto_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_STANDARD_ROOT")
    is Some(root_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_TARGET")
    is Some(target) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY")
    is Some(public_key) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY")
    is Some(bundle_body) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID")
    is Some(bundle_cid) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE")
    is Some(signature) else {
    return
  }
  let sqlite = @native_sqlite.load_library(sqlite_path).unwrap()
  let crypto = @native_signature.load_library(crypto_path).unwrap()
  let root = @native_filesystem.open_root(root_path).unwrap()
  let component = b"native-runtime"
  let writer = root
    .create_writer("runtime-stage", component.length().to_int64())
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
      "runtime-process:standard-local",
    )
    .unwrap()
  let site = @site.create_site(
    "native-standard-site", 1, bundle_cid, 2, 2, 1048576L, 268435456L,
  ).unwrap()
  let journal_control = @remote.create_site_dispatch_journal(
    site, "actql-remote-site/0.1",
  ).unwrap()
  let journal = @native_remote_journal.open_journal(
    sqlite,
    root_path + "/standard-journal.sqlite3",
    262144L,
    journal_control,
  ).unwrap()
  let (local_captured, local_run, local_query_issuer) = prepare_native_publication_local_run()
  let local_graph = @strategy.captured_dag_graph(local_captured)
  let run_definition_cid = @strategy.graph_program_definition_cid(local_graph)
  let (duckdb_captured, duckdb_run, duckdb_query_issuer) = prepare_native_publication_duckdb_run(
    duckdb_path,
  )
  let duckdb_graph = @strategy.captured_dag_graph(duckdb_captured)
  assert_eq(
    @strategy.graph_program_definition_cid(duckdb_graph),
    run_definition_cid,
  )
  let input_binding = @remote.prepare_remote_input_binding("{}", 16).unwrap()
  let local_run_owner = [Some(local_run)]
  let local_input_finished = [false]
  let local_executor = @native_remote_standard.install_native_remote_standard_task_executor(
    run_definition_cid,
    "task-1-local",
    1,
    (request, binding) => {
      if @remote.remote_input_binding_body(binding) != "{}" {
        return Err("foreign standard input")
      }
      match local_run_owner[0] {
        Some(value) => {
          local_run_owner[0] = None
          @native_remote_standard.bind_native_remote_standard_run(
            request,
            binding,
            value,
            () => {
              if !local_input_finished[0] {
                @mock.close_mock_query_issuer(local_query_issuer)
                local_input_finished[0] = true
              }
              true
            },
          ).map_err(_ => "standard input binding")
        }
        None => Err("standard Run already opened")
      }
    },
    {
      output_export: native_publication_export_limits(),
      max_manifest_bytes: 65536,
      max_retained_bytes: 1048576L,
    },
  ).unwrap()
  let duckdb_run_owner = [Some(duckdb_run)]
  let duckdb_input_finished = [false]
  let duckdb_executor = @native_remote_standard.install_native_remote_standard_task_executor(
    run_definition_cid,
    "task-1-duckdb",
    1,
    (request, binding) => {
      if @remote.remote_input_binding_body(binding) != "{}" {
        return Err("foreign standard input")
      }
      match duckdb_run_owner[0] {
        Some(value) => {
          duckdb_run_owner[0] = None
          @native_remote_standard.bind_native_remote_standard_run(
            request,
            binding,
            value,
            () => {
              if !duckdb_input_finished[0] {
                @mock.close_mock_query_issuer(duckdb_query_issuer)
                duckdb_input_finished[0] = true
              }
              true
            },
          ).map_err(_ => "standard input binding")
        }
        None => Err("standard Run already opened")
      }
    },
    {
      output_export: native_publication_export_limits(),
      max_manifest_bytes: 65536,
      max_retained_bytes: 1048576L,
    },
  ).unwrap()
  let foreign_run_opens = [0]
  let foreign_binding = @remote.prepare_remote_input_binding(
    "{\"foreign\":true}", 32,
  ).unwrap()
  let foreign_executor = @native_remote_standard.install_native_remote_standard_task_executor(
    run_definition_cid,
    "task-1-foreign-binding",
    1,
    (_, binding) => {
      if @remote.remote_input_binding_cid(binding) !=
        @remote.remote_input_binding_cid(foreign_binding) {
        return Err("foreign standard input")
      }
      foreign_run_opens[0] += 1
      Err("foreign dispatch opened a Run")
    },
    {
      output_export: native_publication_export_limits(),
      max_manifest_bytes: 65536,
      max_retained_bytes: 1048576L,
    },
  ).unwrap()
  let operation_capability = native_publication_cid(
    "remote-standard-operation-capability",
  )
  let issuer_capability = native_publication_cid(
    "remote-standard-issuer-capability",
  )
  let local_budget = @remote.prepare_remote_dispatch_budget(1048576L, 1048576L).unwrap()
  let duckdb_budget = @remote.prepare_remote_dispatch_budget(
    1048576L, 134217728L,
  ).unwrap()
  let runtime = @native_remote_standard.open_native_remote_standard_site_runtime(
    site,
    active_runtime,
    operation_capability,
    issuer_capability,
    [local_executor, duckdb_executor, foreign_executor],
    journal,
    bundles,
    [local_budget, duckdb_budget],
  ).unwrap()
  let (connector_registration, connector_revision, strategy_revision) = @native_runtime_bundle.native_active_runtime_connector_scope(
    active_runtime,
  )
  let local_request = @remote.prepare_dispatch_request(
    "native-standard-coordinator",
    run_definition_cid,
    "task-1-local",
    1,
    "native-standard-local-dispatch-1",
    "native-standard-site",
    1,
    bundle_cid,
    connector_registration,
    connector_revision,
    strategy_revision,
    @remote.remote_input_binding_cid(input_binding),
    native_publication_cid("remote-standard-obligations"),
    @remote.remote_dispatch_budget_cid(local_budget),
    issuer_capability,
    operation_capability,
  ).unwrap()
  assert_native_remote_standard_output(
    runtime, journal, local_request, input_binding, "[{\"id\":3}]",
  )
  let duckdb_request = @remote.prepare_dispatch_request(
    "native-standard-coordinator",
    run_definition_cid,
    "task-1-duckdb",
    1,
    "native-standard-duckdb-dispatch-1",
    "native-standard-site",
    1,
    bundle_cid,
    connector_registration,
    connector_revision,
    strategy_revision,
    @remote.remote_input_binding_cid(input_binding),
    native_publication_cid("remote-standard-obligations"),
    @remote.remote_dispatch_budget_cid(duckdb_budget),
    issuer_capability,
    operation_capability,
  ).unwrap()
  assert_native_remote_standard_output(
    runtime, journal, duckdb_request, input_binding, "[{\"id\":3}]",
  )
  let foreign_request = @remote.prepare_dispatch_request(
    "native-standard-coordinator",
    run_definition_cid,
    "task-1-foreign-binding",
    1,
    "native-standard-foreign-binding-dispatch-1",
    "native-standard-site",
    1,
    bundle_cid,
    connector_registration,
    connector_revision,
    strategy_revision,
    @remote.remote_input_binding_cid(input_binding),
    native_publication_cid("remote-standard-obligations"),
    @remote.remote_dispatch_budget_cid(local_budget),
    issuer_capability,
    operation_capability,
  ).unwrap()
  let foreign_operation = @remote.admit_remote_poll_operation_json(
    @remote.remote_poll_dispatch_json(foreign_request, input_binding).unwrap(),
  ).unwrap()
  let acknowledge_foreign_acceptance = fn(request) {
    let (_, record) = journal.accept(request).unwrap()
    Ok(record)
  }
  let observe_foreign_status = fn(request) {
    let observed = journal.observation(request).unwrap()
    Ok(Some(@native_remote_journal.recovered_site_dispatch_record(observed)))
  }
  guard @native_remote_agent.advance_native_outbound_operation(
      runtime,
      Some(foreign_operation),
      acknowledge_foreign_acceptance,
      observe_foreign_status,
    )
    is Err(
      @native_remote_agent.RuntimeObserved(
        @native_remote_runtime.Physical("standard-input-resolve"),
        _
      )
    ) else {
    fail("foreign input binding did not fail through the Agent")
  }
  assert_eq(foreign_run_opens[0], 0)
  assert_true(runtime.cleanup(foreign_request).unwrap())
  assert_true(runtime.close().unwrap())
  assert_true(journal.close())
  assert_true(bundles.close().unwrap())
  assert_true(local_input_finished[0])
  assert_true(duckdb_input_finished[0])
  for task = @strategy.graph_task_count(local_graph) - 1
      task > 0
      task = task - 1 {
    @strategy.close_captured_task_output(local_captured, task)
  }
  for task = @strategy.graph_task_count(duckdb_graph) - 1
      task > 0
      task = task - 1 {
    @strategy.close_captured_task_output(duckdb_captured, task)
  }
  for captured in [local_captured, duckdb_captured] {
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(captured))
    assert_eq(usage.reserved_execution_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.held_bytes, 0L)
  }
}

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
fn native_publication_store_failure(
  issue : @native_publication_store.NativePublicationStoreIssue,
) -> String {
  match issue {
    @native_publication_store.UnsupportedTarget => "unsupported target"
    @native_publication_store.Closed => "closed"
    @native_publication_store.InvalidConfiguration => "invalid configuration"
    @native_publication_store.Protocol(_) => "payload protocol"
    @native_publication_store.Filesystem(_) => "filesystem"
    @native_publication_store.Database(_) => "database"
    @native_publication_store.StateCollision => "state collision"
    @native_publication_store.RecoveryRequired => "recovery required"
    @native_publication_store.ExistingPayload => "existing payload"
    @native_publication_store.DigestMismatch => "digest mismatch"
    @native_publication_store.Delivery(_) => "delivery"
    @native_publication_store.RowFrame(_) => "row frame"
    @native_publication_store.SinkProgress(_) => "sink progress"
    @native_publication_store.DeliveryIssuance(_) => "delivery issuance"
    @native_publication_store.DeliveryGrantUsage(_) => "grant usage"
    @native_publication_store.PublicationCommit(issue) =>
      "publication commit " + native_publication_commit_failure(issue)
    @native_publication_store.PublicationCommitIssuance(_) =>
      "publication commit issuance"
    @native_publication_store.PublicationCommitConflict => "commit conflict"
    @native_publication_store.ClockRegression => "clock regression"
    @native_publication_store.DeliveryLimit => "delivery limit"
    @native_publication_store.DeliveryIncomplete => "delivery incomplete"
    @native_publication_store.CleanupPending => "cleanup pending"
    @native_publication_store.ReaderBusy => "reader busy"
    @native_publication_store.ExistingDeliveryAttempt =>
      "existing delivery attempt"
    @native_publication_store.DeliveryAttemptUnresolved =>
      "delivery attempt unresolved"
  }
}

///|
fn native_publication_commit_failure(
  issue : @publication.PublicationCommitIssue,
) -> String {
  match issue {
    @publication.CommitEvidence(_) => "evidence chain"
    @publication.CommitResultEvidence(value) =>
      "result evidence " + native_result_evidence_failure(value)
    @publication.CommitWrongContract(name) => "wrong contract " + name
    @publication.CommitReferenceMismatch(field) => "reference mismatch " + field
    @publication.CommitInventoryMismatch => "inventory mismatch"
    @publication.CommitEncoding => "encoding"
  }
}

///|
fn native_result_evidence_failure(
  issue : @publication.ResultEvidenceSetIssue,
) -> String {
  match issue {
    @publication.ResultEvidenceCount => "count"
    @publication.ResultEvidenceMissingDefinition => "missing definition"
    @publication.ResultEvidenceMissingDerivation => "missing derivation"
    @publication.ResultEvidenceMissingOrdering => "missing ordering"
    @publication.ResultEvidenceMissingRetention => "missing retention"
    @publication.ResultEvidenceDuplicate => "duplicate"
    @publication.ResultEvidenceArtifact(_) => "artifact"
    @publication.ResultEvidenceOrdering(_) => "ordering"
  }
}

///|
fn execute_native_publication_local_run() -> @strategy.CapturedDAG raise {
  let (run, issuer) = captured_graph_fixture()
  let registry = search_registry()
  let revision = channel_test_selection(run, registry)
  let registration = @strategy.strategy_registration(revision, 1).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  let limits = dispatch_test_limits()
  let implementation = @local_driver.prepare_local_dispatch_module(
    driver,
    registry,
    registration,
    dispatch_test_generated(run),
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
  ).unwrap()
  let entries = @connector.install_capability_implementations(
    registry,
    [
      (
        registration,
        fn(_context : Unit, task, revision, request) {
          @local_driver.prepare_local_dispatch(
            implementation, task, revision, request,
          )
        },
      ),
    ],
    1,
  ).unwrap()
  let host = @host_driver.open_dispatch_host(
    driver,
    entries,
    limits.capacity,
    100,
    10000,
  ).unwrap()
  while @host_driver.prepare_next_installed_task(host, ()).unwrap()
        is Some(task) {
    @local_driver.execute_local_dispatch(implementation, host, task).unwrap()
  }
  @host_driver.stop_dispatch_driver(driver)
  @mock.close_mock_query_issuer(issuer)
  run
}

///|
fn execute_native_publication_duckdb_run(
  library_path : String,
) -> (@strategy.CapturedDAG, @native_host.NativeStrategyComputeRun) raise {
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
  let driver = @host_driver.open_dispatch_driver(run)
  let limits = duckdb_dispatch_module_limits()
  let implementation = @duckdb_driver.prepare_duckdb_dispatch_module(
    driver,
    registry,
    registration,
    dispatch_test_generated(run).map(
      @execution.generated_completion_preparation,
    ),
    limits,
  ).unwrap()
  let entries = @connector.install_capability_implementations(
    registry,
    [
      (
        registration,
        fn(_context : Unit, task, selected, request) {
          @duckdb_driver.prepare_duckdb_dispatch(
            implementation, task, selected, request,
          )
        },
      ),
    ],
    1,
  ).unwrap()
  let host = @host_driver.open_dispatch_host(
    driver,
    entries,
    limits.capacity,
    100,
    10000,
  ).unwrap()
  let library = @native_duckdb.load_library(library_path).unwrap()
  let runtime_owner = @native_host.open_native_strategy_compute_run()
  let mut complete = false
  while !complete {
    let expected_task = @strategy.next_captured_task(run).unwrap_or(-1)
    let task = match @host_driver.prepare_next_installed_task(host, ()) {
      Ok(Some(value)) => value
      Ok(None) => {
        complete = true
        continue
      }
      Err(NoStrategy) => abort("DuckDB publication has no strategy")
      Err(MissingImplementation) =>
        abort("DuckDB publication is missing an implementation")
      Err(Dispatch(PendingTask)) =>
        abort("DuckDB publication left a pending task")
      Err(Dispatch(StaleTask)) => abort("DuckDB publication task is stale")
      Err(Dispatch(Run(UnsupportedGraph))) =>
        abort("DuckDB publication graph is unsupported")
      Err(Dispatch(Run(ForeignCapture))) =>
        abort("DuckDB publication capture is foreign")
      Err(Dispatch(Run(NotReady))) =>
        abort("DuckDB publication task is not ready")
      Err(Dispatch(Run(Stopped))) => abort("DuckDB publication Run stopped")
      Err(Dispatch(Run(ForeignCandidate))) =>
        abort("DuckDB publication candidate is foreign")
      Err(Dispatch(Run(MissingOutput))) =>
        abort(
          "DuckDB publication output is missing for task " +
          expected_task.to_string(),
        )
      Err(Dispatch(Run(Capture(_)))) =>
        abort("DuckDB publication source capture failed")
      Err(Dispatch(Run(Binding(_)))) =>
        abort("DuckDB publication input binding failed")
      Err(Dispatch(Run(Read(_)))) =>
        abort("DuckDB publication input read failed")
      Err(Dispatch(Run(Compute(_)))) =>
        abort("DuckDB publication compute preparation failed")
      Err(Dispatch(Run(Implementation(_)))) =>
        abort("DuckDB publication implementation failed")
      Err(Dispatch(Run(Physical(_)))) =>
        abort("DuckDB publication physical admission failed")
      Err(Dispatch(Candidate(_))) =>
        abort("DuckDB publication request admission failed")
      Err(Implementation(_)) => abort("DuckDB publication preparation failed")
    }
    let setup = @duckdb_driver.take_duckdb_dispatch(implementation, host, task).unwrap()
    let database = library.open_database().unwrap()
    ignore(
      @native_host.execute_native_strategy_compute_task(
        runtime_owner,
        setup,
        database,
        native_compute_import_limits(),
        100000L,
        1000000L,
      ).unwrap(),
    )
  }
  assert_eq(
    @native_host.native_strategy_compute_run_task_count(runtime_owner),
    3,
  )
  @host_driver.stop_dispatch_driver(driver)
  @mock.close_mock_query_issuer(issuer)
  (run, runtime_owner)
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
fn verify_native_publication_run(
  run : @strategy.CapturedDAG,
  token : String,
  sqlite_library_path : String,
  root : String,
  duckdb_runtime_owner? : @native_host.NativeStrategyComputeRun? = None,
) -> Unit raise {
  let graph = @strategy.captured_dag_graph(run)
  let exports = [
    @publication_host.prepare_captured_result_publication_export(
      run,
      0,
      native_publication_export_limits(),
    ).unwrap(),
    @publication_host.prepare_captured_result_publication_export(
      run,
      1,
      native_publication_export_limits(),
    ).unwrap(),
  ]
  let definitions = exports.map(output => output.definition().unwrap())
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
  let preparation = @native_run_publication.prepare_effect_free_run_publication_native(
    service,
    run_context.run_definition,
    definitions,
    intent,
    occurrence,
  ).unwrap()
  let attempt = preparation.publication_attempt()
  let published : Array[@native_run_publication.NativePublishedOutput] = []
  for index, output in exports {
    published.push(
      @native_run_publication.persist_publication_output_native(
        store,
        output,
        {
          run_definition: run_context.run_definition,
          invocation: run_context.invocation,
          retention: retentions[index],
          publication_attempt: attempt,
          computation_contract_cid: native_publication_cid(
            token + "-compute-" + index.to_string(),
          ),
          input_relation_cids: [],
          scope_cid: native_publication_cid(
            token + "-scope-" + index.to_string(),
          ),
          effective_data_policy_cid: native_publication_cid(
            token + "-data-policy",
          ),
          authority_scope_cid: intent.authority_scope_cid,
          store_authority_cid: authority,
          material_generation_cid: native_publication_cid(
            token + "-material-" + index.to_string(),
          ),
          max_payload_bytes: 10000L,
        },
        65536,
        4096,
        32,
      ).unwrap(),
    )
  }
  assert_eq(published.length(), 2)
  for output in published {
    assert_eq(
      output.payload.publication_attempt_cid,
      @publication.publication_contract_identity(attempt),
    )
  }
  let capacity_before_rejection = store.capacity_usage().unwrap()
  let oversized = @publication_host.prepare_captured_result_publication_export(
    run,
    1,
    native_publication_export_limits(),
  ).unwrap()
  assert_true(
    @native_run_publication.persist_publication_output_native(
      store,
      oversized,
      {
        run_definition: run_context.run_definition,
        invocation: run_context.invocation,
        retention: retentions[1],
        publication_attempt: attempt,
        computation_contract_cid: native_publication_cid(
          token + "-oversized-compute",
        ),
        input_relation_cids: [],
        scope_cid: native_publication_cid(token + "-oversized-scope"),
        effective_data_policy_cid: native_publication_cid(
          token + "-data-policy",
        ),
        authority_scope_cid: intent.authority_scope_cid,
        store_authority_cid: authority,
        material_generation_cid: native_publication_cid(
          token + "-oversized-material",
        ),
        max_payload_bytes: 1L,
      },
      65536,
      4096,
      32,
    )
    is Err(@native_run_publication.InvalidOutputConfiguration),
  )
  let capacity_after_rejection = store.capacity_usage().unwrap()
  assert_eq(
    capacity_after_rejection.reserved_bytes,
    capacity_before_rejection.reserved_bytes,
  )
  assert_eq(
    capacity_after_rejection.reserved_objects,
    capacity_before_rejection.reserved_objects,
  )
  let evidence = @native_run_publication.assemble_native_effect_free_publication(
    run_context, published, 65536, 4096, 32,
  ).unwrap()
  let committed = match
    @native_run_publication.commit_prepared_effect_free_run_publication_native(
      service, evidence, intent, occurrence, preparation,
    ) {
    Ok(value) => value
    Err(@native_run_publication.InvalidConfiguration) =>
      abort("publication invalid configuration")
    Err(@native_run_publication.AccessDenied) =>
      abort("publication access denied")
    Err(@native_run_publication.CommitConflict) =>
      abort("publication commit conflict")
    Err(@native_run_publication.Store(issue)) =>
      abort(
        "publication Store failure: " + native_publication_store_failure(issue),
      )
    Err(@native_run_publication.Issuance(_)) =>
      abort("publication issuance failure")
    Err(@native_run_publication.Commit(_)) => abort("publication chain failure")
    Err(@native_run_publication.Projection(_)) =>
      abort("publication projection failure")
  }
  assert_true(committed.committed)
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
  match duckdb_runtime_owner {
    Some(owner) =>
      assert_true(
        @native_host.close_native_strategy_compute_run(owner).unwrap(),
      )
    None => ()
  }
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
  verify_native_publication_run(
    execute_native_publication_local_run(),
    token,
    sqlite_library_path,
    root,
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
  let (run, runtime_owner) = execute_native_publication_duckdb_run(
    duckdb_library_path,
  )
  verify_native_publication_run(
    run,
    token,
    sqlite_library_path,
    root,
    duckdb_runtime_owner=Some(runtime_owner),
  )
}

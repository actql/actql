///|
fn publication_test_cid(value : String) -> String {
  "sha256:" + @sha.hex(@utf8.encode(value))
}

///|
fn publication_test_contract(
  name : String,
  body : String,
) -> @publication.PublicationContract {
  @publication.seal_publication_contract(name, body, 65536, 4096, 32).unwrap()
}

///|
fn publication_test_evidence(
  name : String,
  body : String,
) -> @publication.RunEvidenceValue {
  @publication.seal_run_evidence_value(name, body, 65536, 4096, 32).unwrap()
}

///|
fn publication_test_logical_cid(rows_wire : String) -> String {
  let source = @source.parse_json(rows_wire, {
    max_input_bytes: 65536,
    max_nodes: 4096,
    max_depth: 32,
  }).unwrap()
  let rows = @json.from_source(source, 4096, 32, 65536) catch {
    _ => abort("invalid publication rows")
  }
  let writer = @encode.hashing_writer(65536, 4096, 32) catch {
    _ => abort("invalid Relation writer")
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "sort")
    @encode.string_value(writer, "relation")
    @encode.key(writer, "value")
    @json.emit_value(rows, writer)
    @encode.end_object(writer)
    let (digest, _, _) = @encode.finish_hash_usage(writer)
    "sha256:" + digest
  } catch {
    _ => abort("invalid Relation identity")
  }
}

///|
fn publication_test_fixture(
  store : @store.Store,
  authority : String,
  token : String,
) -> (
  NativeEffectFreePublicationEvidence,
  NativeRunPublicationIntent,
  NativeRunPublicationOccurrence,
) {
  let program_cid = publication_test_cid(token + "-program")
  let template = publication_test_evidence(
    "bound_invocation_template",
    "{\"version\":\"actql-bound-invocation-template/0.1\"," +
    "\"program_definition_cid\":\"" +
    program_cid +
    "\",\"parameter_values_cid\":\"" +
    publication_test_cid(token + "-parameters") +
    "\",\"invocation_bindings_cid\":\"" +
    publication_test_cid(token + "-bindings") +
    "\",\"check_environment_cid\":\"" +
    publication_test_cid(token + "-environment") +
    "\",\"grammar_manifest_cid\":\"" +
    publication_test_cid(token + "-grammar") +
    "\",\"required_profile_contracts\":[]," +
    "\"barrier_contract_manifest_cid\":\"" +
    publication_test_cid(token + "-barriers") +
    "\",\"source_evidence\":\"unbound\"}",
  )
  let plan = publication_test_contract(
    "compiled_plan",
    "{\"version\":\"actql-compiled-plan/0.1\"," +
    "\"compiler_version\":\"compiler-0.1\"," +
    "\"aoa_ir_version\":\"aoa-ir-0.1\"," +
    "\"executable_plan_cid\":\"" +
    publication_test_cid(token + "-executable") +
    "\",\"program_definition_cid\":\"" +
    program_cid +
    "\",\"program_semantics_cid\":\"" +
    publication_test_cid(token + "-semantics") +
    "\",\"aoa_contract_cid\":\"" +
    publication_test_cid(token + "-aoa-contract") +
    "\",\"aoa_logical_cid\":\"" +
    publication_test_cid(token + "-aoa-logical") +
    "\"}",
  )
  let execution_context_cid = publication_test_cid(token + "-execution")
  let host_policy_cid = publication_test_cid(token + "-host-policy")
  let prepared = publication_test_evidence(
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
  let authorization = publication_test_evidence(
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
    publication_test_cid(token + "-inputs"),
    "2026-09-20T00:00:00.000Z",
    "2026-09-21T04:00:00.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let observation = publication_test_evidence(
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
    publication_test_cid(token + "-observation-policy") +
    "\"}",
  )
  let invocation = @publication.issue_run_invocation(
    template, observation, 65536, 4096, 32,
  ).unwrap()
  let definition = @publication.result_definition_contract(
    @publication.prepare_result_definition(program_cid, "answer").unwrap(),
  )
  let rows_wire = "[{\"value\":7}]"
  let schema_wire = "{\"value\":{\"nullable\":false,\"type\":\"integer\"}}"
  let logical_cid = publication_test_logical_cid(rows_wire)
  let schema_cid = publication_test_cid(schema_wire)
  let data_policy_cid = publication_test_cid(token + "-data-policy")
  let authority_scope_cid = publication_test_cid(token + "-authority-scope")
  let result_evidence = @publication.issue_result_occurrence_evidence(
    definition,
    logical_cid,
    schema_cid,
    publication_test_cid(token + "-compute"),
    [],
    publication_test_cid(token + "-result-scope"),
    data_policy_cid,
    "actql-native-host",
    authority_scope_cid,
    65536,
    4096,
    32,
  ).unwrap()
  let ordering = @publication.result_ordering_evidence_contract(result_evidence)
  let derivation = @publication.result_ordering_derivation_contract(
    result_evidence,
  )
  let retention = publication_test_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\"," +
    "\"retention_contract_cid\":\"" +
    publication_test_cid(token + "-retention") +
    "\",\"effective_data_policy_cid\":\"" +
    data_policy_cid +
    "\",\"available_until\":\"2026-09-21T00:00:00.000Z\"," +
    "\"delete_by\":\"2026-09-22T00:00:00.000Z\"," +
    "\"extension_ceiling_at\":\"2026-09-22T00:00:00.000Z\"," +
    "\"metadata_retention_policy_cid\":\"" +
    publication_test_cid(token + "-metadata-policy") +
    "\",\"metadata_delete_by\":\"2026-09-23T00:00:00.000Z\"," +
    "\"clock_contract_cid\":\"" +
    publication_test_cid(token + "-clock") +
    "\"}",
  )
  let artifact = @publication.issue_complete_result_artifact(
    definition, invocation, result_evidence, retention, 1, 65536, 4096, 32,
  ).unwrap()
  let manifest = @publication.issue_result_manifest(
    run_definition,
    invocation,
    [definition],
    [artifact],
    65536,
    4096,
    32,
  ).unwrap()
  let journal = publication_test_evidence(
    "normalization_journal",
    "{\"version\":\"actql-normalization-journal/0.1\"," +
    "\"rule_catalog_cid\":\"" +
    publication_test_cid(token + "-rules") +
    "\",\"entries\":[]}",
  )
  let receipt = @publication.issue_effect_free_run_receipt(
    admission,
    run_definition,
    invocation,
    observation,
    [definition],
    [artifact],
    manifest,
    journal,
    [],
    [],
    [],
    [],
    [],
    65536,
    4096,
    32,
  ).unwrap()
  let snapshot = @publication.admit_captured_result_snapshot(
    definition,
    artifact,
    rows_wire,
    ["value"],
    65536,
    4096,
    32,
  ).unwrap()
  let authoring = publication_test_evidence(
    "authoring_context",
    "{\"version\":\"actql-authoring-context/0.1\"," +
    "\"program_definition_cid\":\"" +
    program_cid +
    "\",\"annotations\":[]}",
  )
  let captured_run = @publication.issue_effect_free_captured_run(
    run_definition,
    invocation,
    [definition],
    [artifact],
    manifest,
    receipt,
    [snapshot],
    [],
    authoring,
    [],
    65536,
    4096,
    32,
  ).unwrap()
  let codec_cid = publication_test_cid(token + "-codec")
  let payload_request = @payload.prepare_publication_payload_request(
    authority,
    publication_test_cid(token + "-payload-attempt"),
    publication_test_cid(token + "-material"),
    @publication.publication_contract_identity(definition),
    logical_cid,
    schema_cid,
    @publication.publication_contract_identity(ordering),
    codec_cid,
    64L,
    1L,
  ).unwrap()
  let writer = store.begin_payload(payload_request).unwrap()
  writer.append(@utf8.encode(rows_wire)).unwrap()
  let payload = writer.seal().unwrap()
  let binding = @publication.issue_durable_result_binding(
    run_definition,
    definition,
    invocation,
    artifact,
    ordering,
    retention,
    codec_cid,
    ["value"],
    schema_wire,
    payload.material_generation_cid,
    authority,
    1,
    payload.generation.size.to_int(),
    payload.physical_digest[7:].to_owned(),
    65536,
    4096,
    32,
  ).unwrap()
  (
    {
      run_definition,
      invocation,
      definitions: [definition],
      artifacts: [artifact],
      derivations: [derivation],
      orderings: [ordering],
      retentions: [retention],
      bindings: [binding],
      binding_schema_wires: [schema_wire],
      manifest,
      receipt,
      captured_run,
    },
    {
      namespace_id: "namespace_id",
      authority_scope_cid,
      publication_policy_cid: publication_test_cid(token + "-policy"),
      publication_target_cid: publication_test_cid(token + "-target"),
      requested_at: "2026-09-20T00:00:00.000Z",
    },
    {
      attempt_id: token + "-attempt",
      fence_cid: publication_test_cid(token + "-fence"),
      external_idempotency_key: None,
      started_at: "2026-09-20T00:00:01.000Z",
      committed_at: "2026-09-20T00:00:02.000Z",
    },
  )
}

///|
test "standard native publication reconciles one durable Run commit" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(library_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(root) else {
    return
  }
  let token = "standard-publication-" + @env.now().to_string()
  let authority = publication_test_cid(token + "-store-authority")
  let library = @sqlite.load_library(library_path).unwrap()
  let store = @store.open_store(library, root, authority, 1024L, 8L, 65536L).unwrap()
  let authorization_stages : Array[String] = []
  let publication_authority = install_native_run_publication_authority(fn(
    authorization,
  ) {
    authorization_stages.push(authorization.stage)
    true
  })
  let service = install_native_run_publication_service(
    store, publication_authority, 65536, 4096, 32,
  ).unwrap()
  let (evidence, intent, occurrence) = publication_test_fixture(
    store, authority, token,
  )
  let first = publish_effect_free_run_native(
    service, evidence, intent, occurrence,
  ).unwrap()
  assert_true(first.committed)
  assert_false(first.idempotent)
  let retry_occurrence : NativeRunPublicationOccurrence = {
    attempt_id: token + "-retry-attempt",
    fence_cid: publication_test_cid(token + "-retry-fence"),
    external_idempotency_key: Some("retry-key"),
    started_at: "2026-09-20T00:00:03.000Z",
    committed_at: "2026-09-20T00:00:04.000Z",
  }
  let retry_result = publish_effect_free_run_native(
    service, evidence, intent, retry_occurrence,
  )
  guard retry_result is Ok(retry) else { fail("retry should reconcile") }
  assert_false(retry.committed)
  assert_true(retry.idempotent)
  assert_eq(retry.public_index_entry_cid, first.public_index_entry_cid)
  assert_eq(retry.publication_attempt_cid, first.publication_attempt_cid)
  assert_eq(authorization_stages, [
    "request", "commit", "request", "return_committed",
  ])
  let conflicting_intent : NativeRunPublicationIntent = {
    ..intent,
    publication_policy_cid: publication_test_cid(token + "-other-policy"),
  }
  assert_true(
    publish_effect_free_run_native(
      service, evidence, conflicting_intent, retry_occurrence,
    )
    is Err(CommitConflict),
  )
  let denied = install_native_run_publication_service(
    store,
    install_native_run_publication_authority(fn(_) { false }),
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(
    publish_effect_free_run_native(denied, evidence, intent, retry_occurrence)
    is Err(AccessDenied),
  )
  assert_true(store.close().unwrap())
  let reopened = @store.open_store(library, root, authority, 1024L, 8L, 65536L).unwrap()
  let reopened_service = install_native_run_publication_service(
    reopened, publication_authority, 65536, 4096, 32,
  ).unwrap()
  let after_restart = publish_effect_free_run_native(
    reopened_service, evidence, intent, retry_occurrence,
  ).unwrap()
  assert_true(after_restart.idempotent)
  assert_eq(after_restart.public_index_entry_cid, first.public_index_entry_cid)
  assert_true(reopened.close().unwrap())
}

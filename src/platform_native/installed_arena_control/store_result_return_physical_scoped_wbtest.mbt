///|
/// This selected physical counter uses the existing publication fixture's
/// normative bodies and actual Store payload, not a synthetic delivery handle.
fn store_result_payload_cid(label : String) -> String {
  "sha256:" + @sha.hex(@utf8.encode(label))
}

///|
fn store_result_contract(
  name : String,
  body : String,
) -> @publication.PublicationContract {
  @publication.seal_publication_contract(name, body, 65536, 512, 16).unwrap()
}

///|
priv struct NativePublicationCommitFixture {
  run_definition : @publication.PublicationContract
  invocation : @publication.PublicationContract
  definitions : Array[@publication.PublicationContract]
  artifacts : Array[@publication.PublicationContract]
  derivations : Array[@publication.PublicationContract]
  orderings : Array[@publication.PublicationContract]
  retentions : Array[@publication.PublicationContract]
  bindings : Array[@publication.PublicationContract]
  manifest : @publication.PublicationContract
  receipt : @publication.PublicationContract
  captured_run : @publication.PublicationContract
  request : @publication.PublicationContract
  attempt : @publication.PublicationContract
  index : @publication.PublicationContract
  material_generation_cid : String
  schema_wire : String
}

///|
fn store_result_commit_plan(
  program_cid : String,
  token : String,
) -> @publication.PublicationContract {
  store_result_contract(
    "compiled_plan",
    "{\"version\":\"actql-compiled-plan/0.1\"," +
    "\"compiler_version\":\"compiler-0.1\"," +
    "\"aoa_ir_version\":\"aoa-ir-0.1\"," +
    "\"executable_plan_cid\":\"" +
    store_result_payload_cid(token + "-executable") +
    "\",\"program_definition_cid\":\"" +
    program_cid +
    "\",\"program_semantics_cid\":\"" +
    store_result_payload_cid(token + "-semantics") +
    "\",\"aoa_contract_cid\":\"" +
    store_result_payload_cid(token + "-aoa-contract") +
    "\",\"aoa_logical_cid\":\"" +
    store_result_payload_cid(token + "-aoa-logical") +
    "\"}",
  )
}

///|
fn store_result_commit_evidence(
  name : String,
  body : String,
) -> @publication.RunEvidenceValue {
  @publication.seal_run_evidence_value(name, body, 65536, 4096, 32).unwrap()
}

///|
fn store_result_commit_fixture(
  store : @store.Store,
  store_authority_cid : String,
  token : String,
) -> NativePublicationCommitFixture {
  let program_cid = store_result_payload_cid(token + "-program")
  let template = store_result_commit_evidence(
    "bound_invocation_template",
    "{\"version\":\"actql-bound-invocation-template/0.1\"," +
    "\"program_definition_cid\":\"" +
    program_cid +
    "\",\"parameter_values_cid\":\"" +
    store_result_payload_cid(token + "-parameters") +
    "\",\"invocation_bindings_cid\":\"" +
    store_result_payload_cid(token + "-bindings") +
    "\",\"check_environment_cid\":\"" +
    store_result_payload_cid(token + "-environment") +
    "\",\"grammar_manifest_cid\":\"" +
    store_result_payload_cid(token + "-grammar") +
    "\",\"required_profile_contracts\":[]," +
    "\"barrier_contract_manifest_cid\":\"" +
    store_result_payload_cid(token + "-barriers") +
    "\",\"source_evidence\":\"unbound\"}",
  )
  let plan = store_result_commit_plan(program_cid, token)
  let execution_context_cid = store_result_payload_cid(token + "-execution")
  let host_policy_cid = store_result_payload_cid(token + "-host-policy")
  let prepared = store_result_commit_evidence(
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
  let authorization = store_result_commit_evidence(
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
    store_result_payload_cid(token + "-inputs"),
    "2026-09-20T00:00:00.000Z",
    "2026-09-21T04:00:00.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let observation = store_result_commit_evidence(
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
    store_result_payload_cid(token + "-observation-policy") +
    "\"}",
  )
  let invocation = @publication.issue_run_invocation(
    template, observation, 65536, 4096, 32,
  ).unwrap()
  let definition = @publication.result_definition_contract(
    @publication.prepare_result_definition(program_cid, "answer").unwrap(),
  )
  let row_wire = "[{\"value\":7}]"
  let schema_wire = "{\"value\":{\"nullable\":false,\"type\":\"integer\"}}"
  let rows_source = @source.parse_json(row_wire, {
    max_input_bytes: 65536,
    max_nodes: 4096,
    max_depth: 32,
  }).unwrap()
  let rows = @json.from_source(rows_source, 4096, 32, 65536) catch {
    _ => abort("invalid native publication rows fixture")
  }
  let relation_writer = @encode.hashing_writer(65536, 4096, 32) catch {
    _ => abort("invalid native publication Relation writer")
  }
  let logical_cid = try {
    @encode.begin_object(relation_writer)
    @encode.key(relation_writer, "sort")
    @encode.string_value(relation_writer, "relation")
    @encode.key(relation_writer, "value")
    @json.emit_value(rows, relation_writer)
    @encode.end_object(relation_writer)
    let (digest, _, _) = @encode.finish_hash_usage(relation_writer)
    "sha256:" + digest
  } catch {
    _ => abort("invalid native publication Relation identity")
  }
  let schema_cid = store_result_payload_cid(schema_wire)
  let data_policy_cid = store_result_payload_cid(token + "-data-policy")
  let authority_scope_cid = store_result_payload_cid(token + "-authority-scope")
  let evidence = @publication.issue_result_occurrence_evidence(
    definition,
    logical_cid,
    schema_cid,
    store_result_payload_cid(token + "-compute"),
    [],
    store_result_payload_cid(token + "-result-scope"),
    data_policy_cid,
    "actql-native-host",
    authority_scope_cid,
    65536,
    4096,
    32,
  ).unwrap()
  let ordering = @publication.result_ordering_evidence_contract(evidence)
  let derivation = @publication.result_ordering_derivation_contract(evidence)
  let retention = store_result_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\"," +
    "\"retention_contract_cid\":\"" +
    store_result_payload_cid(token + "-retention") +
    "\",\"effective_data_policy_cid\":\"" +
    data_policy_cid +
    "\",\"available_until\":\"2026-09-21T00:00:00.000Z\"," +
    "\"delete_by\":\"2026-09-22T00:00:00.000Z\"," +
    "\"extension_ceiling_at\":\"2026-09-22T00:00:00.000Z\"," +
    "\"metadata_retention_policy_cid\":\"" +
    store_result_payload_cid(token + "-metadata-policy") +
    "\",\"metadata_delete_by\":\"2026-09-23T00:00:00.000Z\"," +
    "\"clock_contract_cid\":\"" +
    store_result_payload_cid(token + "-clock") +
    "\"}",
  )
  let artifact = @publication.issue_complete_result_artifact(
    definition, invocation, evidence, retention, 1, 65536, 4096, 32,
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
  let journal = store_result_commit_evidence(
    "normalization_journal",
    "{\"version\":\"actql-normalization-journal/0.1\"," +
    "\"rule_catalog_cid\":\"" +
    store_result_payload_cid(token + "-rules") +
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
  let snapshot = match
    @publication.admit_captured_result_snapshot(
      definition,
      artifact,
      row_wire,
      ["value"],
      65536,
      4096,
      32,
    ) {
    Ok(value) => value
    Err(@publication.CaptureIssuanceReferenceMismatch(field)) =>
      abort("native publication snapshot reference: " + field)
    Err(@publication.CaptureIssuanceInvalidRows(field)) =>
      abort("native publication snapshot rows: " + field)
    Err(@publication.CaptureIssuanceInvalidFields(field)) =>
      abort("native publication snapshot fields: " + field)
    Err(_) => abort("invalid native publication snapshot")
  }
  let authoring = store_result_commit_evidence(
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
  let codec_cid = store_result_payload_cid(token + "-codec")
  let payload_request = @payload.prepare_publication_payload_request(
    store_authority_cid,
    store_result_payload_cid(token + "-payload-attempt"),
    store_result_payload_cid(token + "-material"),
    @publication.publication_contract_identity(definition),
    logical_cid,
    schema_cid,
    @publication.publication_contract_identity(ordering),
    codec_cid,
    64L,
    1L,
  ).unwrap()
  let writer = store.begin_payload(payload_request).unwrap()
  writer.append(@utf8.encode(row_wire)).unwrap()
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
    store_authority_cid,
    1,
    payload.generation.size.to_int(),
    payload.physical_digest[7:].to_owned(),
    65536,
    4096,
    32,
  ).unwrap()
  let request = @publication.issue_publication_request(
    run_definition,
    [definition],
    "namespace_id",
    authority_scope_cid,
    store_result_payload_cid(token + "-publication-policy"),
    store_result_payload_cid(token + "-publication-target"),
    "2026-09-20T00:00:00.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let attempt = @publication.issue_publication_attempt(
    request,
    run_definition,
    token + "-publication-attempt",
    store_result_payload_cid(token + "-fence"),
    None,
    "2026-09-20T00:00:01.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let index = @publication.issue_public_index_entry(
    run_definition,
    invocation,
    manifest,
    receipt,
    captured_run,
    [binding],
    request,
    attempt,
    "2026-09-20T00:00:02.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  {
    run_definition,
    invocation,
    definitions: [definition],
    artifacts: [artifact],
    derivations: [derivation],
    orderings: [ordering],
    retentions: [retention],
    bindings: [binding],
    manifest,
    receipt,
    captured_run,
    request,
    attempt,
    index,
    material_generation_cid: payload.material_generation_cid,
    schema_wire,
  }
}

///|
fn commit_store_result_fixture(
  store : @store.Store,
  fixture : NativePublicationCommitFixture,
) -> Result[@store.NativePublicationCommit, @store.NativePublicationStoreIssue] {
  store.commit_publication(
    fixture.run_definition,
    fixture.invocation,
    fixture.definitions,
    fixture.artifacts,
    fixture.derivations,
    fixture.orderings,
    fixture.retentions,
    fixture.bindings,
    [fixture.schema_wire],
    fixture.manifest,
    fixture.receipt,
    fixture.captured_run,
    fixture.request,
    fixture.attempt,
    fixture.index,
    65536,
    4096,
    32,
  )
}

///|
test "successful formal Result acquisition survives lost original return until child ACK" {
  store_wal_physical_case(false, open_probe=6)
}

///|
fn store_result_return_work(
  library : @sqlite.Library,
  original : @sqlite.NativeStoreOperationOriginal,
  receiver : StoreWalReceiver,
  path : String,
) -> Bool raise {
  let authority = store_result_payload_cid("formal-return-authority")
  let store = @store.open_original_local_store_with_custody(
    library,
    original,
    path,
    authority,
    256L,
    8L,
    65536L,
    diagnostic_ceiling=Some(256),
  ).unwrap()
  let fixture = store_result_commit_fixture(store, authority, "formal-return")
  commit_store_result_fixture(store, fixture).unwrap() |> ignore
  let grant = @publication.issue_result_read_grant(
    fixture.index,
    fixture.manifest,
    ["answer"],
    ["jsonl"],
    "principal",
    "download",
    store_result_payload_cid("ceiling"),
    64,
    1,
    "2026-09-21T00:00:00.000Z",
    store_result_payload_cid("authorization"),
    store_result_payload_cid("egress"),
    65536,
    512,
    16,
  ).unwrap()
  // All actual durable publication and grant checks precede the injected loss.
  // The body acquires its real Reader; only its SAME original return fails.
  receiver.fail_normal_return = true
  assert_true(
    store.begin_result_delivery(
      fixture.index,
      fixture.manifest,
      grant,
      fixture.retentions[0],
      fixture.bindings[0],
      fixture.material_generation_cid,
      "answer",
      "jsonl",
      "formal-return-delivery",
      "2026-09-20T01:00:00.000Z",
      fixture.schema_wire,
      ["value"],
      3,
      64,
      65536,
      512,
      16,
      64L,
    )
    is Err(@store.OperationRouting(None, _)),
  )
  let sql_before = receiver.sql_entries
  let normal_before = receiver.normal_entries
  assert_true(store.close() is Err(@store.CleanupPending))
  assert_true(original.close_checked() is Err(_))
  assert_true(library.close_checked() is Err(_))
  receiver.fail_cleanup_return = true
  assert_true(
    store.retry_pending_result_delivery_cleanup()
    is Err(@store.OperationRouting(_, _)),
  )
  assert_true(store.close() is Err(@store.CleanupPending))
  assert_eq(receiver.sql_entries, sql_before)
  assert_eq(receiver.normal_entries, normal_before)
  // Recovery returns the original flight, then closes the retained child only.
  // Neither acquisition, attempt/grant claiming nor SQL is replayed.
  assert_true(store.retry_pending_result_delivery_cleanup().unwrap())
  assert_false(store.retry_pending_result_delivery_cleanup().unwrap())
  assert_eq(receiver.sql_entries, sql_before)
  assert_eq(receiver.normal_entries, normal_before)
  assert_true(store.capacity_usage() is Err(_))
  assert_eq(store_wal_library_children(library), 1)
  assert_true(store.close().unwrap())
  original.close_checked().unwrap()
  original.primary_code() == 33 && original.cleanup_code() == 44
}

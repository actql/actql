///|
priv struct AccessPublicationFixture {
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
  authority_scope_cid : String
  schema_wire : String
}

///|
fn native_access_cid(label : String) -> String {
  "sha256:" + @sha.hex(@utf8.encode(label))
}

///|
fn native_access_contract(
  name : String,
  body : String,
) -> @publication.PublicationContract {
  @publication.seal_publication_contract(name, body, 65536, 4096, 32).unwrap()
}

///|
fn native_access_evidence(
  name : String,
  body : String,
) -> @publication.RunEvidenceValue {
  @publication.seal_run_evidence_value(name, body, 65536, 4096, 32).unwrap()
}

///|
fn native_access_fixture(
  store : @store.Store,
  store_authority_cid : String,
  token : String,
) -> AccessPublicationFixture {
  let program_cid = native_access_cid(token + "-program")
  let template = native_access_evidence(
    "bound_invocation_template",
    "{\"version\":\"actql-bound-invocation-template/0.1\"," +
    "\"program_definition_cid\":\"" +
    program_cid +
    "\",\"parameter_values_cid\":\"" +
    native_access_cid(token + "-parameters") +
    "\",\"invocation_bindings_cid\":\"" +
    native_access_cid(token + "-bindings") +
    "\",\"check_environment_cid\":\"" +
    native_access_cid(token + "-environment") +
    "\",\"grammar_manifest_cid\":\"" +
    native_access_cid(token + "-grammar") +
    "\",\"required_profile_contracts\":[]," +
    "\"barrier_contract_manifest_cid\":\"" +
    native_access_cid(token + "-barriers") +
    "\",\"source_evidence\":\"unbound\"}",
  )
  let plan = native_access_contract(
    "compiled_plan",
    "{\"version\":\"actql-compiled-plan/0.1\"," +
    "\"compiler_version\":\"compiler-0.1\"," +
    "\"aoa_ir_version\":\"aoa-ir-0.1\"," +
    "\"executable_plan_cid\":\"" +
    native_access_cid(token + "-executable") +
    "\",\"program_definition_cid\":\"" +
    program_cid +
    "\",\"program_semantics_cid\":\"" +
    native_access_cid(token + "-semantics") +
    "\",\"aoa_contract_cid\":\"" +
    native_access_cid(token + "-aoa-contract") +
    "\",\"aoa_logical_cid\":\"" +
    native_access_cid(token + "-aoa-logical") +
    "\"}",
  )
  let execution_context_cid = native_access_cid(token + "-execution")
  let host_policy_cid = native_access_cid(token + "-host-policy")
  let prepared = native_access_evidence(
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
  let authorization = native_access_evidence(
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
    native_access_cid(token + "-inputs"),
    "2026-09-20T00:00:00.000Z",
    "2026-09-21T04:00:00.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let observation = native_access_evidence(
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
    native_access_cid(token + "-observation-policy") +
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
    _ => abort("invalid native access rows fixture")
  }
  let relation_writer = @encode.hashing_writer(65536, 4096, 32) catch {
    _ => abort("invalid native access Relation writer")
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
    _ => abort("invalid native access Relation identity")
  }
  let schema_cid = native_access_cid(schema_wire)
  let data_policy_cid = native_access_cid(token + "-data-policy")
  let authority_scope_cid = native_access_cid(token + "-authority-scope")
  let evidence = @publication.issue_result_occurrence_evidence(
    definition,
    logical_cid,
    schema_cid,
    native_access_cid(token + "-compute"),
    [],
    native_access_cid(token + "-result-scope"),
    data_policy_cid,
    "actql-native-host",
    authority_scope_cid,
    65536,
    4096,
    32,
  ).unwrap()
  let ordering = @publication.result_ordering_evidence_contract(evidence)
  let derivation = @publication.result_ordering_derivation_contract(evidence)
  let retention = native_access_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\"," +
    "\"retention_contract_cid\":\"" +
    native_access_cid(token + "-retention") +
    "\",\"effective_data_policy_cid\":\"" +
    data_policy_cid +
    "\",\"available_until\":\"2026-09-21T00:00:00.000Z\"," +
    "\"delete_by\":\"2026-09-22T00:00:00.000Z\"," +
    "\"extension_ceiling_at\":\"2026-09-22T00:00:00.000Z\"," +
    "\"metadata_retention_policy_cid\":\"" +
    native_access_cid(token + "-metadata-policy") +
    "\",\"metadata_delete_by\":\"2026-09-23T00:00:00.000Z\"," +
    "\"clock_contract_cid\":\"" +
    native_access_cid(token + "-clock") +
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
  let journal = native_access_evidence(
    "normalization_journal",
    "{\"version\":\"actql-normalization-journal/0.1\"," +
    "\"rule_catalog_cid\":\"" +
    native_access_cid(token + "-rules") +
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
    row_wire,
    ["value"],
    65536,
    4096,
    32,
  ).unwrap()
  let authoring = native_access_evidence(
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
  let codec_cid = native_access_cid(token + "-codec")
  let payload_request = @payload.prepare_publication_payload_request(
    store_authority_cid,
    native_access_cid(token + "-payload-attempt"),
    native_access_cid(token + "-material"),
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
    "tenant",
    authority_scope_cid,
    native_access_cid(token + "-publication-policy"),
    native_access_cid(token + "-publication-target"),
    "2026-09-20T00:00:00.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let attempt = @publication.issue_publication_attempt(
    request,
    run_definition,
    token + "-publication-attempt",
    native_access_cid(token + "-fence"),
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
    authority_scope_cid,
    schema_wire,
  }
}

///|
fn commit_access_fixture(
  store : @store.Store,
  fixture : AccessPublicationFixture,
) -> Unit {
  ignore(
    store
    .commit_publication(
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
    .unwrap(),
  )
}

///|
fn consume_native_access(session : NativeResultAccessSession) -> String {
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
test "standard native access delivers and reauthorizes after restart" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(library_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(root) else {
    return
  }
  let token = "native-access-" + @env.now().to_string()
  let store_authority = native_access_cid(token + "-store-authority")
  let library = @sqlite.load_library(library_path).unwrap()
  let store = @store.open_store(
    library, root, store_authority, 256L, 8L, 65536L,
  ).unwrap()
  let fixture = native_access_fixture(store, store_authority, token)
  commit_access_fixture(store, fixture)
  let mut admission_generation = 0
  let authority = install_native_result_access_authority(
    request => request.principal_id == "principal",
    facts => {
      if facts.request.result_name != "answer" {
        return None
      }
      admission_generation = admission_generation + 1
      Some({
        authorization_context_cid: native_access_cid(
          token + "-authorization-" + admission_generation.to_string(),
        ),
        data_ceiling_cid: native_access_cid(token + "-ceiling"),
        egress_admission_cid: native_access_cid(
          token + "-egress-" + admission_generation.to_string(),
        ),
        expires_at: "2026-09-21T00:00:00.000Z",
        max_bytes: 64,
        max_uses: 1,
      })
    },
    authorization => {
      authorization.request.principal_id == "principal" &&
      (authorization.stage == "read" || authorization.stage == "receipt")
    },
  )
  let service = install_native_result_access_service(
    store,
    authority,
    () => "2026-09-20T01:00:00.000Z",
    65536,
    4096,
    32,
    65536,
    3,
  ).unwrap()
  let base_request : NativeResultAccessRequest = {
    tenant_id: "tenant",
    authority_scope_cid: fixture.authority_scope_cid,
    run_definition_cid: @publication.publication_contract_identity(
      fixture.run_definition,
    ),
    principal_id: "principal",
    purpose: "download",
    result_name: "answer",
    format: "jsonl",
    attempt_id: token + "-delivery-1",
  }
  let first = open_native_result_access(service, base_request).unwrap()
  assert_eq(consume_native_access(first), "{\"value\":7}\n")
  let mut clock_step = 0
  let expiring_authority = install_native_result_access_authority(
    _ => true,
    _ => {
      Some({
        authorization_context_cid: native_access_cid(
          token + "-expiring-authorization",
        ),
        data_ceiling_cid: native_access_cid(token + "-expiring-ceiling"),
        egress_admission_cid: native_access_cid(token + "-expiring-egress"),
        expires_at: "2026-09-20T01:00:00.000Z",
        max_bytes: 64,
        max_uses: 1,
      })
    },
    _ => true,
  )
  let expiring_service = install_native_result_access_service(
    store,
    expiring_authority,
    () => {
      clock_step = clock_step + 1
      if clock_step < 3 {
        "2026-09-20T01:00:00.000Z"
      } else {
        "2026-09-20T01:00:00.001Z"
      }
    },
    65536,
    4096,
    32,
    65536,
    3,
  ).unwrap()
  let expiring = open_native_result_access(expiring_service, {
    ..base_request,
    attempt_id: token + "-expiring",
  }).unwrap()
  assert_true(expiring.next(3) is Err(ResultUnavailable))
  assert_eq(
    expiring.terminate(None, false, "exact", None, None).unwrap().state,
    "failed",
  )
  assert_true(store.close().unwrap())
  let reopened = @store.open_store(
    library, root, store_authority, 256L, 8L, 65536L,
  ).unwrap()
  let restarted = install_native_result_access_service(
    reopened,
    authority,
    () => "2026-09-20T01:00:01.000Z",
    65536,
    4096,
    32,
    65536,
    3,
  ).unwrap()
  let second = open_native_result_access(restarted, {
    ..base_request,
    attempt_id: token + "-delivery-2",
  }).unwrap()
  assert_eq(consume_native_access(second), "{\"value\":7}\n")
  assert_true(
    open_native_result_access(restarted, {
      ..base_request,
      principal_id: "denied",
      attempt_id: token + "-denied",
    })
    is Err(AccessDenied),
  )
  assert_true(reopened.close().unwrap())
}

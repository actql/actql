///|
// Real checked Values execution, publication outputs and Native Store. These
// internal Host fixtures do not establish installed CLI or Account acceptance.
test "actual Values publication supplies succeeded state with unknown Result availability" {
  let (database, journal, epoch, reference) = submitted_test_setup(
    "values-state-observation",
  )
  let scope = "sha256:" + "a".repeat(64)
  let (intent, preparation, request, original_compiled, definition) = submitted_run_test_input(
    reference, "values-state-original",
  )
  guard preparation.preparation is Computation(prepared) else {
    fail("expected actual original Values preparation")
  }
  let assets = @host.client_local_product_assets()
  let policy_cid = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  let compiled = @host.with_client_source_free_result_policy(
    original_compiled,
    policy_cid,
    assets.result_policy,
    65536,
    8192,
    64,
  ).unwrap()
  journal
  .record_submitted_intent(epoch, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  journal
  .accept_submitted_run(
    epoch, reference, preparation, request, compiled, definition, scope, true, 1001.0,
  )
  .unwrap()
  |> ignore
  // Retain exact issued policy bytes before first start in this existing
  // journal. No Source policy or empty completion journal is fabricated.
  let policy_wire = run_policy_originals_wire(prepared, compiled~).unwrap()
  journal
  .transaction(() => {
    let row = journal.retained(request).unwrap().unwrap()
    journal.save({ ..row, publication_policy_originals: Some(policy_wire), })
  })
  .unwrap()
  |> ignore
  let work = match
    open_native_client_local_values_work(
      journal,
      request,
      prepared,
      compiled,
      definition,
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      16,
      1000,
      () => true,
    ) {
    Ok(value) => value
    Err(failure) => {
      assert_true(failure.close())
      fail("Values execution fixture unavailable")
    }
  }
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap()
  let store_authority = "sha256:" + "c".repeat(64)
  let store = @publication_store.open_store(
    library, root, store_authority, 65536L, 8L, 131072L,
  ).unwrap()
  let (row_limits, limits) = @local.client_local_values_publication_limits(
    prepared, 65536,
  ).unwrap()
  let retention = @publication.seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\",\"retention_contract_cid\":\"" +
    policy_cid +
    "\",\"effective_data_policy_cid\":\"" +
    policy_cid +
    "\",\"available_until\":\"2099-01-01T00:00:00.000Z\",\"delete_by\":\"2099-01-02T00:00:00.000Z\",\"extension_ceiling_at\":\"2099-01-02T00:00:00.000Z\",\"metadata_retention_policy_cid\":\"" +
    policy_cid +
    "\",\"metadata_delete_by\":\"2099-01-03T00:00:00.000Z\",\"clock_contract_cid\":\"" +
    policy_cid +
    "\"}",
    65536,
    8192,
    64,
  ).unwrap()
  let results : Array[
    @native_publication.NativeCapturedResultPublicationContext,
  ] = @host.client_compiled_run_result_names(compiled).map(_ => {
    retention,
    computation_contract_cid: @publication.publication_contract_identity(
      @host.client_compiled_run_plan(compiled),
    ),
    input_relation_cids: [],
    scope_cid: @publication.publication_contract_identity(definition),
    effective_data_policy_cid: policy_cid,
    store_authority_cid: store_authority,
    material_generation_cid: "sha256:" + "d".repeat(64),
    max_payload_bytes: 65536L,
  })
  let authoring = @publication.seal_run_evidence_value(
    "authoring_context",
    "{\"version\":\"actql-authoring-context/0.1\",\"program_definition_cid\":\"" +
    @host.client_request_program_cid(request) +
    "\",\"annotations\":[]}",
    65536,
    8192,
    64,
  ).unwrap()
  let service = work
    .install_publication_service(
      store,
      "local-test",
      _ => true,
      65536,
      8192,
      64,
    )
    .unwrap()
  let publication_intent : @native_publication.NativeRunPublicationIntent = {
    namespace_id: "local-test",
    authority_scope_cid: scope,
    publication_policy_cid: "sha256:" + "e".repeat(64),
    publication_target_cid: store_authority,
    requested_at: "2026-10-15T00:00:00.000Z",
  }
  let occurrence : @native_publication.NativeRunPublicationOccurrence = {
    attempt_id: "original-state-publication",
    fence_cid: "sha256:" + "f".repeat(64),
    external_idempotency_key: None,
    started_at: "2026-10-15T00:00:00.000Z",
    committed_at: "2026-10-15T00:00:01.000Z",
  }
  let pending = work
    .prepare_local_publication(
      service,
      results,
      authoring,
      publication_intent,
      occurrence,
      row_limits,
      limits.max_result_workspace_entries,
      65536,
      limits,
      65536,
      8192,
      64,
    )
    .unwrap()
  assert_true(
    pending.observe_run_state(
      "2026-10-15T00:00:02.000Z",
      limits.max_result_workspace_entries,
      16,
      1000,
      () => true,
    )
    is Err(Unavailable),
  )
  pending.commit().unwrap() |> ignore
  assert_true(
    pending.observe_run_state(
      "2026-10-15T00:00:02.000Z",
      limits.max_result_workspace_entries,
      16,
      1000,
      () => false,
    )
    is Err(Publication(AccessDenied)),
  )
  let observed = pending
    .observe_run_state(
      "2026-10-15T00:00:02.000Z",
      limits.max_result_workspace_entries,
      16,
      1000,
      () => true,
    )
    .unwrap()
  assert_eq(
    observed.definition_cid(),
    @publication.publication_contract_identity(definition),
  )
  // Independent status/availability oracle; this is not a payload read grant.
  let source = @source.parse_json_bytes_preserving(
    @utf8.encode(observed.wire()),
    { max_input_bytes: 65536, max_nodes: 8192, max_depth: 64, },
  ).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 8192,
    max_depth: 64,
    max_string_bytes: 65536,
    max_total_string_bytes: 65536,
  }).unwrap()
  let body = @decode.open_object(cursor).unwrap()
  assert_eq(epoch_text(body, "run_id"), Some("values-state-original"))
  assert_eq(epoch_text(body, "status"), Some("succeeded"))
  assert_true(observed.wire().contains("unknown"))
  assert_true(observed.wire().contains("verification_pending"))
  assert_true(
    pending.observe_run_state("2026-10-15T00:00:02.000Z", 1, 16, 1000, () => {
      true
    })
    is Err(_),
  )
  assert_true(work.close())
  store.close().unwrap() |> ignore
  assert_true(
    pending.observe_run_state(
      "2026-10-15T00:00:02.000Z",
      limits.max_result_workspace_entries,
      16,
      1000,
      () => true,
    )
    is Err(_),
  )
  database.close_checked().unwrap() |> ignore
}

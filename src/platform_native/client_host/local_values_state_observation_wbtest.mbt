///|
let observed_state_account_original : Bytes = b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"explicit-state-purposes\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\"]},\"operation\":{\"any_of\":[\"publish\",\"read\",\"submit\"]},\"exclusions\":[]}]}"

///|
// Fresh explicit file selection through the original installation Owner, not
// an automatic grant or a product-default permission change.
fn observed_state_host_fixture(
  name : String,
  read : Bool,
) -> NativeLocalHostConnection raise {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = @filesystem.open_private_root(path).unwrap()
  let writer = root.create_writer(name + ".run.stage", 4096L).unwrap()
  writer
  .append(
    @utf8.encode(
      "{\"version\":\"actql-config/0.1\",\"native\":{\"run\":{\"namespace_id\":\"local-test\",\"store_authority_cid\":\"sha256:" +
      "c".repeat(64) +
      "\"}}}",
    ),
  )
  .unwrap()
  writer.seal(name + ".run.json").unwrap() |> ignore
  policy_host_fixture(
    name,
    files=[name + ".run.json"],
    account_body=if read {
      observed_state_account_original
    } else {
      @utf8.encode(
        @utf8.decode(observed_state_account_original).replace(
          old="\"read\",",
          new="",
        ),
      )
    },
  )
}

///|
// Original real Values/SQLite/Store fixture. No old Run, fake Store or Provider.
test "typed Local Host terminal fence accepts actual state and refuses purpose or original loss" {
  let host_name = "values-state-observation"
  let host = observed_state_host_fixture(host_name, true)
  let journal = host.journal
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let epoch = host.epoch
  let token = epoch.issue_epoch(scope, true, 1000.0).unwrap()
  let reference = prepare_native_client_submission_reference(
    token, "original-state-submit",
  ).unwrap()
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    preparation_values_document() +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let preparation = submitted_prepare(intent).unwrap()
  guard preparation.preparation is Computation(prepared) else {
    fail("actual Values preparation missing")
  }
  let (request, _, original_compiled, definition) = journal_test_prepared_run(
    prepared,
    reference.request_id,
    "values-state-original",
    scope~,
  )
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
  let publisher = host
    .bind_run_publisher(
      crypto,
      "operator",
      "cli",
      request,
      definition,
      host_name + ".run.json",
      store,
    )
    .unwrap()
  let publication_intent : @native_publication.NativeRunPublicationIntent = {
    namespace_id: "local-test",
    authority_scope_cid: scope,
    publication_policy_cid: publisher.publication_policy_cid(),
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
    host.observe_publication_run_state(
      publisher,
      pending,
      "2026-10-15T00:00:02.000Z",
      limits.max_result_workspace_entries,
      16,
      1000,
    )
    is Err(Candidate(Unavailable)),
  )
  pending.commit().unwrap() |> ignore
  let observed = host
    .observe_publication_run_state(
      publisher,
      pending,
      "2026-10-15T00:00:02.000Z",
      limits.max_result_workspace_entries,
      16,
      1000,
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
    host.observe_publication_run_state(
      publisher, pending, "2026-10-15T00:00:02.000Z", 1, 16, 1000,
    )
    is Err(Candidate(_)),
  )
  assert_true(
    host.observe_publication_run_state(
      publisher,
      pending,
      "not-a-time",
      limits.max_result_workspace_entries,
      16,
      1000,
    )
    is Err(Candidate(State(_))),
  )
  // Publisher-only invalidation after callback-based candidate preparation:
  // the actual typed RunRead purpose remains current in the same real Host.
  let candidate = pending
    .prepare_run_state_candidate(
      "2026-10-15T00:00:02.000Z",
      limits.max_result_workspace_entries,
      16,
      1000,
    )
    .unwrap()
  let read_authority = native_local_policy_authority_for(
    host,
    crypto,
    "operator",
    "cli",
    request,
    ReadRunMaterials,
  ).unwrap()
  let before = journal.retained(request).unwrap().unwrap()
  journal
  .transaction(() => {
    journal.save({
      ..before,
      publication_binding: Some("foreign-current-binding"),
    })
  })
  .unwrap()
  |> ignore
  assert_true(read_authority.current_for(journal, request))
  assert_false(publisher.current())
  assert_true(
    host.finalize_observed_run_state_candidate(
      publisher, read_authority, candidate,
    )
    is Err(AuthorizationDenied),
  )
  journal
  .transaction(() => {
    let row = journal.retained(request).unwrap().unwrap()
    journal.save({ ..row, publication_binding: before.publication_binding, })
  })
  .unwrap()
  |> ignore
  assert_true(publisher.current())
  let foreign = {
    ..publisher,
    request: journal_test_run(
      "foreign-state-request",
      "foreign-state-run",
      scope~,
    ).0,
  }
  assert_true(
    host.finalize_observed_run_state_candidate(
      foreign, read_authority, candidate,
    )
    is Err(ForeignOriginal),
  )
  candidate.release().unwrap()
  assert_true(work.close())
  assert_true(store.close().unwrap())
  assert_true(
    host.observe_publication_run_state(
      publisher,
      pending,
      "2026-10-15T00:00:02.000Z",
      limits.max_result_workspace_entries,
      16,
      1000,
    )
    is Err(Candidate(Publication(Store(@publication_store.Closed)))),
  )
  host.close().unwrap() |> ignore
}

///|
test "typed Local Host requires independent RunRead even with current Publisher" {
  let name = "state-publish-without-read"
  let host = observed_state_host_fixture(name, false)
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    name,
    name + "-run",
    scope~,
  )
  host.journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let base = @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap()
  @filesystem.open_private_root(base).unwrap().create_directory(name).unwrap()
  |> ignore
  let store = @publication_store.open_store(
    local_journal_test_library(),
    base + "/" + name,
    "sha256:" + "c".repeat(64),
    65536L,
    8L,
    131072L,
  ).unwrap()
  let publication = install_native_client_cancellation_publication(
    store, "local-test", 65536, 8192, 64,
  ).unwrap()
  host.journal
  .bind_installed_publication(request, publication, () => true)
  .unwrap()
  |> ignore
  let publisher = host
    .bind_run_publisher(
      crypto,
      "operator",
      "cli",
      request,
      definition,
      name + ".run.json",
      store,
    )
    .unwrap()
  assert_true(publisher.current())
  assert_true(
    native_local_policy_authority_for(
      host,
      crypto,
      "operator",
      "cli",
      request,
      ReadRunMaterials,
    )
    is Err(AuthorizationDenied),
  )
  assert_true(publisher.current())
  assert_true(store.close().unwrap())
  host.close().unwrap() |> ignore
}

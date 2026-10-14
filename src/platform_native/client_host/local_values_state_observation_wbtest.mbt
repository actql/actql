///|
// Real checked Values execution, publication outputs and Native Store. These
// internal Host fixtures do not establish installed CLI or Account acceptance.
test "actual Values publication supplies succeeded state with unknown Result availability" {
  let host_name = "values-state-observation"
  let host = policy_host_fixture(
    host_name,
    account_body=policy_reuse_account_original,
  )
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
    fail("expected actual original Values preparation")
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
  assert_true(
    host.lookup_submitted_run_state(
      crypto, "operator", "cli", reference, request, 1001.0,
    )
    is Err(Unavailable),
  )
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
  let run_before = journal.retained(request).unwrap().unwrap()
  let submitted_before = journal
    .retained_submission(reference)
    .unwrap()
    .unwrap()
  let saved = host
    .retain_submitted_run_state(
      crypto, "operator", "cli", reference, request, observed, store, "local-test",
      1002.0,
    )
    .unwrap()
  assert_eq(saved.wire(), observed.wire())
  assert_eq(saved.control_revision(), run_before.revision)
  let submitted_after = journal.retained_submission(reference).unwrap().unwrap()
  assert_eq(submitted_after.revision, submitted_before.revision + 1L)
  assert_eq(
    submitted_after.run_admission.unwrap().revision,
    submitted_before.run_admission.unwrap().revision,
  )
  assert_eq(
    run_record_body(journal.retained(request).unwrap().unwrap()).unwrap(),
    run_record_body(run_before).unwrap(),
  )
  assert_eq(
    journal.retained(request).unwrap().unwrap().revision,
    run_before.revision,
  )
  // Same original bytes reuse the saved row after lost-response reconciliation;
  // another observation time cannot replace the immutable first observation.
  host
  .retain_submitted_run_state(
    crypto, "operator", "cli", reference, request, observed, store, "local-test",
    1003.0,
  )
  .unwrap()
  |> ignore
  assert_eq(
    journal.retained_submission(reference).unwrap().unwrap().revision,
    submitted_after.revision,
  )
  assert_true(
    host.retain_submitted_run_state(
      crypto, "operator", "cli", reference, request, observed, store, "foreign-namespace",
      1003.0,
    )
    is Err(ForeignRun),
  )
  assert_true(
    host.lookup_submitted_run_state(
      crypto, "foreign", "cli", reference, request, 1003.0,
    )
    is Err(Journal(AuthorizationDenied)),
  )
  let changed = pending
    .observe_run_state(
      "2026-10-15T00:00:03.000Z",
      limits.max_result_workspace_entries,
      16,
      1000,
      () => true,
    )
    .unwrap()
  assert_true(
    host.retain_submitted_run_state(
      crypto, "operator", "cli", reference, request, changed, store, "local-test",
      1003.0,
    )
    is Err(ChangedIntent),
  )
  let cancellation_publication = install_native_client_cancellation_publication(
    store, "local-test", 65536, 8192, 64,
  ).unwrap()
  let cancellation = journal
    .cancel_operation(
      request,
      "local-test",
      "same-control-revision-after-state",
      run_before.revision.to_int(),
      () => true,
      cancellation_publication,
    )
    .unwrap()
  assert_eq(cancellation.action, @host.AlreadyTerminal)
  assert_eq(cancellation.expected_revision, run_before.revision.to_int())
  assert_eq(
    journal.retained(request).unwrap().unwrap().revision,
    run_before.revision,
  )
  for _ in 0..<2 {
    let restored = host
      .lookup_submitted_run_state(
        crypto, "operator", "cli", reference, request, 1003.0,
      )
      .unwrap()
    assert_eq(restored.wire(), observed.wire())
    assert_eq(restored.control_revision(), run_before.revision)
  }
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
  let read_calls = Ref(0)
  assert_true(
    pending.observe_run_state(
      "2026-10-15T00:00:02.000Z",
      limits.max_result_workspace_entries,
      16,
      1000,
      () => {
        read_calls.val += 1
        read_calls.val < 3
      },
    )
    is Err(Publication(AccessDenied)),
  )
  assert_eq(read_calls.val, 3)
  assert_true(
    pending.observe_run_state(
      "invalid-time",
      limits.max_result_workspace_entries,
      16,
      1000,
      () => true,
    )
    is Err(State(_)),
  )
  assert_true(work.close())
  let close_calls = Ref(0)
  assert_true(
    pending.observe_run_state(
      "2026-10-15T00:00:02.000Z",
      limits.max_result_workspace_entries,
      16,
      1000,
      () => {
        close_calls.val += 1
        if close_calls.val == 3 {
          store.close().unwrap() |> ignore
        }
        true
      },
    )
    is Err(Publication(Store(Closed))),
  )
  assert_eq(close_calls.val, 3)
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
  // Withhold this read transaction's commit reply through the existing SQLite
  // fault port. The committed original is neither missing nor a resend permit.
  submitted_test_fail_commit_after(host.database, 0, true)
  assert_true(
    journal.transaction(() => {
      match journal.saved_run_state_locked(reference, request) {
        Ok((original, _)) => Ok(original.run_state_original)
        Err(issue) => Err(issue)
      }
    })
    is Err(TransactionUnknown),
  )
  host.close().unwrap()
  let reopened = policy_host_fixture(
    host_name,
    existing=true,
    account_body=policy_reuse_account_original,
  )
  let recovered = reopened
    .lookup_submitted_run_state(
      crypto, "operator", "cli", reference, request, 1004.0,
    )
    .unwrap()
  assert_eq(recovered.wire(), observed.wire())
  assert_eq(recovered.control_revision(), run_before.revision)
  reopened.close().unwrap() |> ignore
}

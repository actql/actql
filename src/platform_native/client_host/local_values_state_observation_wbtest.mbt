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
// A Store belongs to this case's existing owned namespace. A global Store
// fixture would also enable unrelated optional cases in the full Core child.
fn observed_state_store_fixture(name : String) -> String {
  let base = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(base).unwrap()
  parent.create_directory(name).unwrap() |> ignore
  parent.close().unwrap()
  base + "/" + name
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
      @local.prepare_installed_sequence_contracts(
        assets.registry,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
      ).unwrap(),
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
  let root = observed_state_store_fixture(host_name + ".store")
  let store_authority = "sha256:" + "c".repeat(64)
  let store = @publication_store.open_store(
    library, root, store_authority, 65536L, 8L, 131072L,
  ).unwrap()
  let (row_limits, limits) = work.publication_limits(65536).unwrap()
  // Match the ordinary Native caller: per-Result row workspace does not
  // supply the separate original bridge and publication-evidence budgets.
  let (bridge_entries, evidence_entries) = work
    .publication_entry_limits()
    .unwrap()
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
      service, results, authoring, publication_intent, occurrence, row_limits, bridge_entries,
      65536, limits, 65536, 8192, 64,
    )
    .unwrap()
  assert_true(
    host.observe_publication_run_state(
      publisher, pending, "2026-10-15T00:00:02.000Z", evidence_entries, 16, 1000,
    )
    is Err(Candidate(Unavailable)),
  )
  let names_original = host
    .lookup_submitted_run_original_by_id(
      crypto, "operator", "cli", "values-state-original",
    )
    .unwrap()
  let before_names_run = run_record_body(
    journal.retained(request).unwrap().unwrap(),
  ).unwrap()
  let before_names_submission = journal
    .retained_submission(reference)
    .unwrap()
    .unwrap().revision
  assert_eq(
    host
    .lookup_original_result_names_json(
      crypto, "operator", "cli", names_original, store, "local-test",
    )
    .unwrap(),
    None,
  )
  assert_eq(
    run_record_body(journal.retained(request).unwrap().unwrap()).unwrap(),
    before_names_run,
  )
  assert_eq(
    journal.retained_submission(reference).unwrap().unwrap().revision,
    before_names_submission,
  )
  // Controlled retention flags exercise only copied metadata in this actual
  // legacy Store fixture. They issue no Native pair, read permission or ACK.
  let data_capture = prepare_native_local_journal_capture(
    host.session,
    library,
    crypto,
    100.0,
    8,
    8388608L,
  )
  data_capture.opening = JournalAcquired(host)
  data_capture.read_callback_active = true
  data_capture.read_facts_valid = true
  journal.operation_active = true
  let definition_cid = @publication.publication_contract_identity(definition)
  assert_true(
    local_committed_result_observation(
      store,
      "local-test",
      scope,
      definition_cid,
      "answer",
      capture=Some(data_capture),
    )
    is Ok(None),
  )
  assert_eq(data_capture.read_committed_results.length(), 0)
  pending.commit().unwrap() |> ignore
  // A real publication changes absence into a positive immutable original.
  // Repeated pure correspondence reuses the same decoded DATA, not another
  // Store resolution, grant, reader or returned scope.
  let committed = local_committed_result_observation(
      store,
      "local-test",
      scope,
      definition_cid,
      "answer",
      capture=Some(data_capture),
    )
    .unwrap()
    .unwrap()
  for _ in 0..<3 {
    let retained = local_committed_result_observation(
        store,
        "local-test",
        scope,
        definition_cid,
        "answer",
        capture=Some(data_capture),
      )
      .unwrap()
      .unwrap()
    assert_true(
      physical_equal(committed.result_manifest, retained.result_manifest),
    )
    assert_true(
      physical_equal(committed.public_index_entry, retained.public_index_entry),
    )
  }
  assert_eq(data_capture.read_committed_results.length(), 1)
  data_capture.read_callback_active = false
  journal.operation_active = false
  data_capture.clear_read_operation_facts()
  assert_eq(data_capture.read_committed_results.capacity(), 0)
  assert_false(data_capture.cleanup_acknowledged)
  let committed_names_run = run_record_body(
    journal.retained(request).unwrap().unwrap(),
  ).unwrap()
  let committed_names_submission = journal
    .retained_submission(reference)
    .unwrap()
    .unwrap().revision
  assert_eq(
    host
    .lookup_original_result_names_json(
      crypto, "operator", "cli", names_original, store, "local-test",
    )
    .unwrap(),
    Some("[\"answer\"]"),
  )
  assert_eq(
    run_record_body(journal.retained(request).unwrap().unwrap()).unwrap(),
    committed_names_run,
  )
  assert_eq(
    journal.retained_submission(reference).unwrap().unwrap().revision,
    committed_names_submission,
  )
  let observed = match
    host.observe_publication_run_state(
      publisher, pending, "2026-10-15T00:00:02.000Z", evidence_entries, 16, 1000,
    ) {
    Ok(value) => value
    Err(Candidate(ValidationLimit)) =>
      fail("original terminal candidate validation workspace exhausted")
    Err(Candidate(InvalidLimits)) =>
      fail("original terminal candidate rejected invalid limits")
    Err(Candidate(Publication(Commit(issue)))) =>
      fail("original terminal candidate commit: " + @debug.to_string(issue))
    Err(Candidate(State(issue))) =>
      fail("original terminal candidate state: " + @debug.to_string(issue))
    Err(Candidate(Publication(AccessDenied))) =>
      fail("original terminal candidate publication authorization denied")
    Err(Candidate(Publication(Store(_)))) =>
      fail("original terminal candidate Store refusal")
    Err(Candidate(Unavailable)) =>
      fail("original terminal candidate unavailable")
    Err(AuthorizationDenied) =>
      fail("original terminal Host authorization denied")
    Err(ForeignOriginal) => fail("original terminal Host foreign original")
    Err(OriginalUnavailable) =>
      fail("original terminal Host original unavailable")
    Err(Journal(_)) => fail("original terminal Host Journal refusal")
    Err(_) => fail("original terminal candidate unavailable at typed Host")
  }
  assert_eq(
    observed.definition_cid(),
    @publication.publication_contract_identity(definition),
  )
  let run_before = journal.retained(request).unwrap().unwrap()
  let submitted_before = journal
    .retained_submission(reference)
    .unwrap()
    .unwrap()
  assert_eq(submitted_before.run_state_observation, Some((0L, None)))
  let saved = host
    .retain_submitted_run_state(
      crypto, "operator", "cli", reference, request, observed, 1002.0,
    )
    .unwrap()
  let saved_wire = saved.wire()
  assert_true(saved_wire.contains("\"revision\":0"))
  assert_eq(saved_wire.replace(old="\"revision\":0,", new=""), observed.wire())
  assert_eq(saved.control_revision(), run_before.revision)
  let submitted_after = journal.retained_submission(reference).unwrap().unwrap()
  let (_, retained_state) = submitted_after.restored_state_original.unwrap()
  let reused = restore_native_saved_run_state(submitted_after, run_before)
    .unwrap()
    .unwrap()
  assert_true(physical_equal(reused.original.unwrap(), retained_state))
  assert_eq(reused.wire(), saved_wire)
  assert_eq(reused.control_revision(), run_before.revision)
  let restored = host
    .lookup_submitted_run_state(
      crypto, "operator", "cli", reference, request, 1002.0,
    )
    .unwrap()
  // A separate public lookup observes its own current snapshot. Pointer
  // identity is required above within the original snapshot, not across calls.
  assert_eq(restored.wire(), saved_wire)
  assert_true(
    restore_native_saved_run_state(
      { ..submitted_after, run_state_original: Some("changed state"), },
      run_before,
    )
    is Err(CustodyLost),
  )
  assert_true(
    restore_native_saved_run_state(
      {
        ..submitted_after,
        run_state_observation: Some((0L, Some("foreign observation"))),
      },
      run_before,
    )
    is Err(CustodyLost),
  )
  let (_, _, _, foreign_definition) = journal_test_run(
    "foreign-state-definition", "foreign-state-definition",
  )
  assert_true(
    restore_native_saved_run_state(submitted_after, {
      ..run_before,
      definition: foreign_definition,
    })
    is Err(CustodyLost),
  )
  assert_true(
    restore_native_saved_run_state(
      { ..submitted_after, run_state_original: None, },
      run_before,
    )
    is Ok(None),
  )
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
  // Same original bytes reuse the saved row after lost-response reconciliation.
  // A different observation timestamp can be stored without logical progress.
  host
  .retain_submitted_run_state(
    crypto, "operator", "cli", reference, request, observed, 1003.0,
  )
  .unwrap()
  |> ignore
  assert_eq(
    journal.retained_submission(reference).unwrap().unwrap().revision,
    submitted_after.revision,
  )
  let foreign = {
    ..observed,
    request: journal_test_run("foreign-retain", "foreign-retain-run", scope~).0,
  }
  assert_true(
    host.retain_submitted_run_state(
      crypto, "operator", "cli", reference, request, foreign, 1003.0,
    )
    is Err(ForeignRun),
  )
  assert_true(
    host.lookup_submitted_run_state(
      crypto, "foreign", "cli", reference, request, 1003.0,
    )
    is Err(Journal(AuthorizationDenied)),
  )
  let changed = host
    .observe_publication_run_state(
      publisher, pending, "2026-10-15T00:00:03.000Z", evidence_entries, 16, 1000,
    )
    .unwrap()
  let changed_saved = host
    .retain_submitted_run_state(
      crypto, "operator", "cli", reference, request, changed, 1003.0,
    )
    .unwrap()
  let latest_saved_wire = changed_saved.wire()
  assert_true(latest_saved_wire.contains("\"revision\":0"))
  assert_true(latest_saved_wire.contains("2026-10-15T00:00:03.000Z"))
  let submitted_changed = journal
    .retained_submission(reference)
    .unwrap()
    .unwrap()
  assert_eq(submitted_changed.revision, submitted_after.revision + 1L)
  assert_eq(
    submitted_changed.run_state_observation,
    submitted_after.run_state_observation,
  )
  assert_eq(submitted_changed.run_state_observation.unwrap().0, 0L)
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
    assert_eq(restored.wire(), latest_saved_wire)
    assert_eq(restored.control_revision(), run_before.revision)
  }
  let selected = host
    .lookup_submitted_run_state_by_id(
      crypto, "operator", "cli", "values-state-original", 1003.0,
    )
    .unwrap()
  assert_eq(selected.state().wire(), latest_saved_wire)
  assert_eq(
    @host.client_request_identity_relation(
      selected.original().request(),
      request,
    ),
    @host.SameRequest,
  )
  assert_eq(
    native_client_submission_reference_wire(selected.original().reference()),
    native_client_submission_reference_wire(selected.reference()),
  )
  assert_eq(
    @publication.publication_contract_identity(selected.original().definition()),
    @publication.publication_contract_identity(selected.definition()),
  )
  assert_eq(
    native_client_submission_reference_wire(selected.reference()),
    reference.wire,
  )
  assert_eq(
    @publication.publication_contract_identity(selected.definition()),
    @publication.publication_contract_identity(definition),
  )
  assert_true(
    host.lookup_submitted_run_state_by_id(
      crypto, "operator", "cli", "never-admitted", 1003.0,
    )
    is Err(Unavailable),
  )
  assert_true(
    host.lookup_submitted_run_state_by_id(
      crypto, "foreign", "cli", "values-state-original", 1003.0,
    )
    is Err(Journal(AuthorizationDenied)),
  )
  // Independent status/availability oracle; this is not a payload read grant.
  let source = @source.parse_json_bytes_preserving(
    @utf8.encode(latest_saved_wire),
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
  assert_true(latest_saved_wire.contains("unknown"))
  assert_true(latest_saved_wire.contains("verification_pending"))
  assert_true(
    host.observe_publication_run_state(
      publisher, pending, "2026-10-15T00:00:02.000Z", 1, 16, 1000,
    )
    is Err(Candidate(_)),
  )
  assert_true(
    host.observe_publication_run_state(
      publisher, pending, "not-a-time", evidence_entries, 16, 1000,
    )
    is Err(Candidate(State(_))),
  )
  // Publisher-only invalidation after callback-based candidate preparation:
  // the actual typed RunRead purpose remains current in the same real Host.
  let candidate = pending
    .prepare_run_state_candidate(
      "2026-10-15T00:00:02.000Z", evidence_entries, 16, 1000,
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
    host.retain_submitted_run_state(
      crypto, "operator", "cli", reference, request, observed, 1003.0,
    )
    is Err(AuthorizationDenied),
  )
  assert_eq(
    journal.retained_submission(reference).unwrap().unwrap().revision,
    submitted_changed.revision,
  )

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
  assert_true(work.publication_limits(65536) is None)
  // A new controlled observation must read the actual Store again. Closing
  // that original afterwards makes retained DATA unavailable; the cache must
  // not bypass actual lifetime or revive the failed operation.
  data_capture.read_callback_active = true
  data_capture.read_facts_valid = true
  journal.operation_active = true
  assert_true(
    local_committed_result_observation(
      store,
      "local-test",
      scope,
      definition_cid,
      "answer",
      capture=Some(data_capture),
    )
    is Ok(Some(_)),
  )
  assert_true(store.close().unwrap())
  assert_true(
    local_committed_result_observation(
      store,
      "local-test",
      scope,
      definition_cid,
      "answer",
      capture=Some(data_capture),
    )
    is Err(PublicationObservation(@publication_store.Closed)),
  )
  assert_false(data_capture.read_facts_valid)
  assert_eq(data_capture.read_committed_results.capacity(), 0)
  assert_true(
    data_capture.read_operation_issue
    is Some(Journal(PublicationObservation(@publication_store.Closed))),
  )
  assert_false(data_capture.cleanup_acknowledged)
  data_capture.read_callback_active = false
  journal.operation_active = false
  assert_true(
    host.lookup_original_result_names_json(
      crypto, "operator", "cli", names_original, store, "local-test",
    )
    is Err(PublicationObservation(@publication_store.Closed)),
  )
  assert_true(
    host.observe_publication_run_state(
      publisher, pending, "2026-10-15T00:00:02.000Z", evidence_entries, 16, 1000,
    )
    is Err(Candidate(Publication(Store(@publication_store.Closed)))),
  )
  let expected_reopen_revision = journal.retained(request).unwrap().unwrap().revision
  host.close().unwrap() |> ignore
  let reopened = policy_host_fixture(
    host_name,
    existing=true,
    files=[host_name + ".run.json"],
    account_body=observed_state_account_original,
  )
  let recovered = reopened
    .lookup_submitted_run_state(
      crypto, "operator", "cli", reference, request, 1004.0,
    )
    .unwrap()
  assert_eq(recovered.wire(), latest_saved_wire)
  assert_eq(recovered.control_revision(), expected_reopen_revision)
  let selected_after_restart = reopened
    .lookup_submitted_run_state_by_id(
      crypto, "operator", "cli", "values-state-original", 1004.0,
    )
    .unwrap()
  assert_eq(selected_after_restart.state().wire(), latest_saved_wire)
  assert_eq(
    selected_after_restart.state().control_revision(),
    expected_reopen_revision,
  )
  // A Run ID is not a unique authorization key. Two authentic Submissions
  // naming it must refuse instead of selecting the first retained row.
  let duplicate_reference = prepare_native_client_submission_reference(
    token, "duplicate-state-submit",
  ).unwrap()
  let duplicate_preparation = submitted_prepare(intent).unwrap()
  guard duplicate_preparation.preparation is Computation(duplicate_prepared) else {
    reopened.close().unwrap() |> ignore
    fail("duplicate fixture preparation: UnsupportedPreparation")
  }
  let (duplicate_request, _, duplicate_compilation, duplicate_definition) = journal_test_prepared_run(
    duplicate_prepared,
    duplicate_reference.request_id,
    "values-state-original",
    scope~,
  )
  let duplicate_compiled = @host.with_client_source_free_result_policy(
    duplicate_compilation,
    policy_cid,
    assets.result_policy,
    65536,
    8192,
    64,
  ).unwrap()
  let reopened_journal = reopened.journal
  reopened_journal
  .record_submitted_intent(
    reopened.epoch,
    duplicate_reference,
    intent,
    scope,
    true,
    1004.0,
  )
  .unwrap()
  |> ignore
  assert_eq(
    @publication.publication_contract_identity(duplicate_definition),
    definition_cid,
  )
  let duplicate_run_before = run_record_body(
    reopened_journal.retained(request).unwrap().unwrap(),
  ).unwrap()
  let duplicate_issued_before = reopened.database
    .read("client_run_custody", "issued")
    .unwrap()
  let duplicate_locator_key = run_id_index_key(scope, "values-state-original")
  let duplicate_locator_before = reopened.database
    .read("client_run_id_index", duplicate_locator_key)
    .unwrap()
  let duplicate_admission = reopened_journal.accept_submitted_run(
    reopened.epoch,
    duplicate_reference,
    duplicate_preparation,
    duplicate_request,
    duplicate_compiled,
    duplicate_definition,
    scope,
    true,
    1004.0,
  )
  if !(duplicate_admission is Err(ForeignRun)) {
    let kind = match duplicate_admission {
      Ok(_) => "unexpected-success"
      Err(issue) => original_selection_journal_kind(issue)
    }
    fail("duplicate original admission: " + kind)
  }
  assert_true(duplicate_admission is Err(ForeignRun))
  assert_eq(
    run_record_body(reopened_journal.retained(request).unwrap().unwrap()).unwrap(),
    duplicate_run_before,
  )
  let duplicate_issued_after = reopened.database
    .read("client_run_custody", "issued")
    .unwrap()
  assert_eq(duplicate_issued_after.body, duplicate_issued_before.body)
  assert_eq(duplicate_issued_after.revision, duplicate_issued_before.revision)
  let duplicate_locator_after = reopened.database
    .read("client_run_id_index", duplicate_locator_key)
    .unwrap()
  assert_eq(duplicate_locator_after.body, duplicate_locator_before.body)
  assert_eq(duplicate_locator_after.revision, duplicate_locator_before.revision)
  assert_true(
    reopened_journal.retained_submission(duplicate_reference).unwrap().unwrap().run_admission
    is None,
  )
  // The existing Owner correctly forbids reusing one exact definition CID.
  // Ambiguity therefore needs two independently issued namespace definitions,
  // each retained under its own authentic new Submission, not a rewritten row.
  let alternate_reference = prepare_native_client_submission_reference(
    token, "alternate-state-submit",
  ).unwrap()
  let (alternate_request, _, alternate_compilation, _) = journal_test_prepared_run(
    duplicate_prepared,
    alternate_reference.request_id,
    "values-state-original",
    scope~,
  )
  let alternate_compiled = @host.with_client_source_free_result_policy(
    alternate_compilation,
    policy_cid,
    assets.result_policy,
    65536,
    8192,
    64,
  ).unwrap()
  let alternate_definition = @host.issue_client_compiled_run_definition(
    alternate_compiled, "alternate-original-namespace", "values-state-original",
    "2026-10-10T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  reopened_journal
  .record_submitted_intent(
    reopened.epoch,
    alternate_reference,
    intent,
    scope,
    true,
    1004.0,
  )
  .unwrap()
  |> ignore
  let alternate_admission = reopened_journal.accept_submitted_run(
    reopened.epoch,
    alternate_reference,
    duplicate_preparation,
    alternate_request,
    alternate_compiled,
    alternate_definition,
    scope,
    true,
    1004.0,
  )
  if alternate_admission is Err(issue) {
    let kind = match issue {
      CustodyLost => "CustodyLost"
      ForeignRun => "ForeignRun"
      ChangedIntent => "ChangedIntent"
      CapacityExceeded => "CapacityExceeded"
      InvalidSubmission => "InvalidSubmission"
      Epoch(_) => "Epoch"
      Start(_) => "Start"
      _ => "OtherTypedIssue"
    }
    reopened.close().unwrap() |> ignore
    fail("alternate fixture accept_submitted_run: " + kind)
  }
  assert_true(
    reopened.lookup_submitted_run_state_by_id(
      crypto, "operator", "cli", "values-state-original", 1004.0,
    )
    is Err(Journal(ForeignRun)),
  )
  assert_eq(
    reopened
    .lookup_submitted_run_state(
      crypto, "operator", "cli", reference, request, 1004.0,
    )
    .unwrap()
    .wire(),
    latest_saved_wire,
  )
  // Historical metadata absence stays unavailable, even when authentic state
  // bytes exist. Do not turn this disposable legacy row into a fresh zero row.
  reopened_journal
  .transaction(() => {
    let row = reopened_journal.retained_submission(reference).unwrap().unwrap()
    let body = submitted_intent_body(
      reference,
      row.intent,
      run_admission=row.run_admission,
      run_state_original=row.run_state_original.map(wire => {
        wire.replace(old="\\\"revision\\\":0,", new="")
      }),
    ).unwrap()
    reopened_journal.database
    .compare_exchange(
      "client_submitted_intents",
      reference.request_id,
      row.revision,
      body,
    )
    .map_err(issue => NativeClientRunJournalIssue::Physical(issue))
  })
  .unwrap()
  |> ignore
  let legacy_read = reopened.lookup_submitted_run_state(
    crypto, "operator", "cli", reference, request, 1004.0,
  )
  let legacy_record = reopened_journal.retained_submission(reference)
  reopened.close().unwrap() |> ignore
  assert_true(legacy_read is Err(Unavailable))
  assert_true(legacy_record.unwrap().unwrap().run_state_observation is None)
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
  let root = observed_state_store_fixture(name + ".store")
  let store = @publication_store.open_store(
    local_journal_test_library(),
    root,
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

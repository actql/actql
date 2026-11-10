///|
// Same exact finite permission set as policy_account_original, explicitly in
// the existing Account Owner's canonical selector order. Never normalize a
// caller's invalid Account or weaken that Owner to make this fixture succeed.
let checkpoint_lookup_account : Bytes = b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"explicit-policy-operations\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"result/answer\",\"run\"]},\"operation\":{\"any_of\":[\"read\",\"submit\"]},\"exclusions\":[]}]}"

///|
// Two simultaneously live original Hosts must not contend on the same
// local-adoption.lock. Only fixture state-parent placement changes; source
// Account, limits, original scope and the production lock remain unchanged.
fn checkpoint_lookup_host_fixture(
  name : String,
  existing? : Bool = false,
) -> NativeLocalHostConnection raise {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = signing_grant_fixture_require(
    @filesystem.open_private_root(path),
    "checkpoint_fixture_source_root",
  )
  let parent = name + ".parent"
  let account = name + ".account.json"
  if !existing {
    signing_grant_fixture_require(
      root.create_directory(parent),
      "checkpoint_fixture_private_parent",
    )
    |> ignore
    let writer = signing_grant_fixture_require(
      root.create_writer(name + ".stage", 4096L),
      "checkpoint_fixture_account_writer",
    )
    signing_grant_fixture_require(
      writer.append(checkpoint_lookup_account),
      "checkpoint_fixture_account_append",
    )
    signing_grant_fixture_require(
      writer.seal(account),
      "checkpoint_fixture_account_seal",
    )
    |> ignore
  }
  signing_grant_fixture_require(root.close(), "checkpoint_fixture_source_close")
  let crypto = epoch_test_crypto()
  let adoption = signing_grant_fixture_require(
    begin_native_local_host_adoption(
      path + "/" + parent,
      name + ".host",
      path,
      account,
      "operator",
      crypto,
      existing_only=existing,
    ),
    "checkpoint_fixture_adoption",
  )
  signing_grant_fixture_require(
    adoption.open_journal(
      local_journal_test_library(),
      crypto,
      100.0,
      8,
      8388608L,
    ),
    "checkpoint_fixture_original_journal",
  )
}

///|
// Journal transaction fixture only: no Provider Preview, Effect execution or
// physical CLI acceptance is represented by this sealed protocol artifact.
fn local_checkpoint_lookup_fixture(
  name : String,
  waiting? : Bool = true,
  admitted? : Bool = true,
) -> (
  NativeLocalHostConnection,
  NativeClientSubmissionReference,
  @host.ClientRequestIdentity,
  @checkpoint.SealedCheckpoint,
) raise {
  let host = checkpoint_lookup_host_fixture(name)
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let epoch = host.epoch.issue_epoch(scope, true, 1000.0).unwrap()
  let reference = prepare_native_client_submission_reference(
    epoch, "checkpoint-original-submit",
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
    fail("missing checked original")
  }
  let (request, _, compiled, definition) = journal_test_prepared_run(
    prepared,
    reference.request_id,
    "checkpoint-run",
    scope~,
  )
  host.journal
  .record_submitted_intent(host.epoch, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  if admitted {
    host.journal
    .accept_submitted_run(
      host.epoch,
      reference,
      preparation,
      request,
      compiled,
      definition,
      scope,
      true,
      1002.0,
    )
    .unwrap()
    |> ignore
  }
  let artifact = checkpoint_test_artifact(definition)
  if waiting {
    host.journal.reserve_dispatch(request, true).unwrap() |> ignore
    assert_true(host.journal.claim_physical_start(request, true).unwrap())
    let before = host.journal.retained(request).unwrap().unwrap()
    host.journal.database
    .insert(
      "test_checkpoint_artifacts",
      artifact.checkpoint_cid,
      @utf8.encode(artifact.wire),
    )
    .unwrap()
    |> ignore
    let retained = @utf8.decode(
      host.journal.database
      .read("test_checkpoint_artifacts", artifact.checkpoint_cid)
      .unwrap().body,
    )
    let persisted = @checkpoint.confirm_checkpoint_persisted(artifact, retained).unwrap()
    host.journal
    .wait_checkpoint(
      request,
      compiled,
      persisted,
      before.revision,
      {
        authorization_context_cid: scope,
        environment_binding_cid: "sha256:" + "b".repeat(64),
      },
      [],
      "2026-10-10T00:00:30.000Z",
      () => true,
    )
    .unwrap()
    |> ignore
  }
  (host, reference, request, artifact)
}

///|
fn local_checkpoint_lookup_call(
  host : NativeLocalHostConnection,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  principal? : String = "operator",
) -> Result[
  NativeClientOriginalCheckpointMetadata?,
  NativeClientOriginalCheckpointLookupIssue,
] {
  host.lookup_submitted_checkpoint_metadata(
    epoch_test_crypto(),
    principal,
    "cli",
    reference,
    request,
    1003.0,
  )
}

///|
test "Native original Checkpoint metadata is readonly and survives authenticated Host reopen" {
  let name = "local-checkpoint-metadata-reopen"
  let (host, reference, request, artifact) = local_checkpoint_lookup_fixture(
    name,
  )
  let before = host.journal.retained(request).unwrap().unwrap()
  let before_wire = run_record_body(before).unwrap()
  for _ in 0..<2 {
    let original = local_checkpoint_lookup_call(host, reference, request)
      .unwrap()
      .unwrap()
    assert_eq(
      native_client_original_checkpoint_cid(original),
      artifact.checkpoint_cid,
    )
    assert_eq(
      native_client_original_checkpoint_revision(original),
      before.revision,
    )
    assert_false(
      native_client_original_checkpoint_cancellation_requested(original),
    )
    assert_eq(
      native_client_original_checkpoint_state(original).status,
      @publication.WaitingCheckpoint,
    )
    assert_eq(
      native_client_original_checkpoint_state(original).run_id,
      "checkpoint-run",
    )
    assert_eq(
      native_client_original_checkpoint_run_cid(original),
      @publication.publication_contract_identity(before.definition),
    )
    assert_eq(
      run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
      before_wire,
    )
  }
  host.close().unwrap()
  let reopened = checkpoint_lookup_host_fixture(name, existing=true)
  let restored = local_checkpoint_lookup_call(reopened, reference, request)
    .unwrap()
    .unwrap()
  assert_eq(
    native_client_original_checkpoint_cid(restored),
    artifact.checkpoint_cid,
  )
  assert_eq(
    native_client_original_checkpoint_revision(restored),
    before.revision,
  )
  assert_eq(
    run_record_body(reopened.journal.retained(request).unwrap().unwrap()).unwrap(),
    before_wire,
  )
  reopened.close().unwrap()
}

///|
test "Native Checkpoint lookup separates cancellation request from retained Checkpoint state" {
  let (host, reference, request, _) = local_checkpoint_lookup_fixture(
    "local-checkpoint-cancel-request",
  )
  let before = host.journal.retained(request).unwrap().unwrap()
  host.journal
  .cancellation_test_operation(
    request,
    "checkpoint-cancel-namespace",
    "checkpoint-cancel-original",
    before.revision.to_int(),
    () => true,
    () => false,
  )
  .unwrap()
  |> ignore
  let accepted = host.journal.retained(request).unwrap().unwrap()
  assert_true(accepted.cancellation_requested)
  let bytes = run_record_body(accepted).unwrap()
  let original = local_checkpoint_lookup_call(host, reference, request)
    .unwrap()
    .unwrap()
  assert_true(
    native_client_original_checkpoint_cancellation_requested(original),
  )
  assert_eq(
    native_client_original_checkpoint_revision(original),
    accepted.revision,
  )
  assert_eq(
    native_client_original_checkpoint_state(original).status,
    @publication.WaitingCheckpoint,
  )
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    bytes,
  )
  host.close().unwrap()
}

///|
test "Native Checkpoint metadata never borrows authority from accepted references" {
  let (host, reference, request, _) = local_checkpoint_lookup_fixture(
    "local-checkpoint-denied",
  )
  let before = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  assert_true(
    local_checkpoint_lookup_call(host, reference, request, principal="other")
    is Err(Journal(AuthorizationDenied)),
  )
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    before,
  )
  host.close().unwrap()
  assert_true(
    local_checkpoint_lookup_call(host, reference, request)
    is Err(Journal(AuthorizationDenied)),
  )
}

///|
test "Native Checkpoint metadata distinguishes an authenticated empty original from unresolved history" {
  let (host, reference, request, _) = local_checkpoint_lookup_fixture(
    "local-checkpoint-empty",
    waiting=false,
  )
  assert_true(
    local_checkpoint_lookup_call(host, reference, request) is Ok(None),
  )
  let other = prepare_native_client_submission_reference(
    reference.epoch,
    "other-submit",
  ).unwrap()
  assert_true(
    local_checkpoint_lookup_call(host, other, request) is Err(UnresolvedHistory),
  )
  let record = host.journal.retained(request).unwrap().unwrap()
  assert_false(record.physical_start_claimed)
  assert_false(record.dispatch_reserved)
  assert_false(record.cancellation_requested)
  host.close().unwrap()
}

///|
test "Native preparing Submission is not an empty original Checkpoint observation" {
  let (host, reference, request, _) = local_checkpoint_lookup_fixture(
    "local-checkpoint-preparing",
    waiting=false,
    admitted=false,
  )
  assert_true(
    local_checkpoint_lookup_call(host, reference, request)
    is Err(MissingRunAdmission),
  )
  assert_true(host.journal.retained(request).unwrap() is None)
  host.close().unwrap()
}

///|
test "Native Checkpoint metadata refuses another original request and missing Run custody" {
  let (host, reference, request, _) = local_checkpoint_lookup_fixture(
    "local-checkpoint-foreign",
  )
  let scope = @host.client_request_authority_scope_cid(request)
  let (foreign, _, _, _) = journal_test_run(
    "foreign-request",
    "foreign-run",
    scope~,
  )
  assert_true(
    local_checkpoint_lookup_call(host, reference, foreign)
    is Err(Journal(ChangedIntent)),
  )
  let before = host.journal.retained(request).unwrap().unwrap()
  let accepted_submission = host.journal
    .retained_submission(reference)
    .unwrap()
    .unwrap()
  let saved_submission = host.database
    .read("client_submitted_intents", reference.request_id)
    .unwrap()
  assert_eq(saved_submission.revision, accepted_submission.revision)
  let table = @utf8.encode("client_runs")
  let key = @utf8.encode(@host.client_request_scope_cid(request))
  assert_true(
    submitted_test_remove_record(
      host.journal.database,
      table,
      table.length(),
      key,
      key.length(),
    ),
  )
  assert_true(
    local_checkpoint_lookup_call(host, reference, request)
    is Err(Journal(CustodyLost)),
  )
  // The accepted Submission is never converted into a replacement Run.
  assert_true(host.journal.retained(request).unwrap() is None)
  // Current admission refuses the missing Run; the independently observed
  // physical Submission must retain its exact accepted bytes and revision.
  assert_true(host.journal.retained_submission(reference) is Err(CustodyLost))
  let after_submission = host.database
    .read("client_submitted_intents", reference.request_id)
    .unwrap()
  assert_eq(after_submission.body, saved_submission.body)
  assert_eq(after_submission.revision, saved_submission.revision)
  assert_eq(accepted_submission.run_admission.unwrap().revision, 0L)
  assert_true(before.physical_start_claimed)
  host.close().unwrap()
}

///|
test "Native saved State reads original Checkpoint lifecycle without a completed Manifest or invented counter" {
  let name = "local-checkpoint-saved-state"
  let (host, reference, request, _) = local_checkpoint_lookup_fixture(name)
  let original = local_checkpoint_lookup_call(host, reference, request)
    .unwrap()
    .unwrap()
  let before = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  let state = host
    .lookup_submitted_run_state(
      epoch_test_crypto(),
      "operator",
      "cli",
      reference,
      request,
      1003.0,
    )
    .unwrap()
  assert_true(state.original is None)
  let submitted = host.journal.retained_submission(reference).unwrap().unwrap()
  let run = host.journal.retained(request).unwrap().unwrap()
  assert_true(
    restore_native_saved_run_state(
      { ..submitted, run_state_observation: Some((1L, None)), },
      run,
    ).unwrap()
    is None,
  )
  assert_true(
    restore_native_saved_run_state(
      { ..submitted, run_state_original: Some("missing original metadata"), },
      run,
    ).unwrap()
    is None,
  )
  assert_eq(
    state.wire(),
    native_client_original_checkpoint_state(original).wire,
  )
  assert_eq(
    state.control_revision(),
    native_client_original_checkpoint_revision(original),
  )
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    before,
  )
  host.close().unwrap()
  let cold = checkpoint_lookup_host_fixture(name, existing=true)
  let saved = cold
    .lookup_submitted_run_state(
      epoch_test_crypto(),
      "operator",
      "cli",
      reference,
      request,
      1004.0,
    )
    .unwrap()
  assert_eq(saved.wire(), state.wire())
  assert_eq(saved.control_revision(), state.control_revision())
  cold.close().unwrap()
}

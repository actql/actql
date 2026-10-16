///|
// Real adopted Account/Epoch/SQLite originals. These fixtures stop at durable
// admission, before execution/publication/state observation; no Provider is used.
fn original_selection_fixture(
  host : NativeLocalHostConnection,
  nonce : String,
  run_id : String,
) -> (
  NativeClientSubmissionReference,
  @host.ClientRequestIdentity,
  @publication.PublicationContract,
) raise {
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let epoch = host.epoch_authority().unwrap()
  let token = epoch.issue_epoch(scope, true, 1000.0).unwrap()
  let reference = prepare_native_client_submission_reference(token, nonce).unwrap()
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    preparation_values_document() +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let preparation = submitted_prepare(intent).unwrap()
  guard native_client_submitted_preparation(preparation)
    is Computation(prepared) else {
    fail("original identity fixture: Computation required")
  }
  let (request, _, compiled, definition) = journal_test_fixture_require(
    journal_test_prepared_run_result(
      prepared,
      reference.request_id,
      run_id,
      scope~,
    ),
  )
  let journal = host.run_journal().unwrap()
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
  (reference, request, definition)
}

///|
test "original Run ID reads exact retained identity without manufacturing absent state" {
  let name = "original-id-no-state"
  let host = policy_host_fixture(name)
  let crypto = epoch_test_crypto()
  let (reference, request, definition) = original_selection_fixture(
    host, "retained-nonce", "retained-run",
  )
  let journal = host.run_journal().unwrap()
  let before = journal.retained(request).unwrap().unwrap()
  let submission_before = journal
    .retained_submission(reference)
    .unwrap()
    .unwrap()
  let selected = host.lookup_submitted_run_original_by_id(
    crypto, "operator", "cli", "retained-run",
  )
  let state = host.lookup_submitted_run_state_by_id(
    crypto, "operator", "cli", "retained-run", 1002.0,
  )
  let after = journal.retained(request).unwrap().unwrap()
  let submission_after = journal
    .retained_submission(reference)
    .unwrap()
    .unwrap()
  host.close().unwrap()
  let selected = selected.unwrap()
  assert_eq(
    native_client_submission_reference_wire(selected.reference()),
    native_client_submission_reference_wire(reference),
  )
  assert_eq(
    @host.client_request_identity_relation(selected.request(), request),
    @host.SameRequest,
  )
  assert_eq(
    @publication.publication_contract_json(selected.definition()),
    @publication.publication_contract_json(definition),
  )
  assert_true(state is Err(Unavailable))
  assert_eq(run_record_body(after).unwrap(), run_record_body(before).unwrap())
  assert_eq(submission_after.revision, submission_before.revision)
  assert_true(submission_after.run_state_original is None)
  assert_true(submission_after.run_state_observation is None)
  assert_false(after.dispatch_reserved)
  assert_false(after.physical_start_claimed)
  let reopened = policy_host_fixture(name, existing=true)
  let restored = reopened.lookup_submitted_run_original_by_id(
    crypto, "operator", "cli", "retained-run",
  )
  reopened.close().unwrap()
  assert_eq(
    native_client_submission_reference_wire(restored.unwrap().reference()),
    native_client_submission_reference_wire(reference),
  )
}

///|
test "original Run ID never interprets unknown ID or nonce as permission for new intake" {
  let host = policy_host_fixture("original-id-missing")
  let crypto = epoch_test_crypto()
  let (reference, request, _) = original_selection_fixture(
    host, "not-a-run-id", "only-original-run",
  )
  let journal = host.run_journal().unwrap()
  let before = journal.retained_submission(reference).unwrap().unwrap()
  let missing = host.lookup_submitted_run_original_by_id(
    crypto, "operator", "cli", "never-admitted",
  )
  let nonce = host.lookup_submitted_run_original_by_id(
    crypto, "operator", "cli", "not-a-run-id",
  )
  let run = journal.retained(request).unwrap().unwrap()
  let after = journal.retained_submission(reference).unwrap().unwrap()
  host.close().unwrap()
  assert_true(missing is Err(Unavailable))
  assert_true(nonce is Err(Unavailable))
  assert_eq(after.revision, before.revision)
  assert_false(run.dispatch_reserved)
  assert_false(run.physical_start_claimed)
}

///|
test "original Run ID requires actual current RunRead independently of submit and supplied identity" {
  let body = @utf8.decode(policy_account_original).replace(
    old="[\"read\",\"submit\"]",
    new="[\"submit\"]",
  )
  let host = policy_host_fixture(
    "original-id-denied",
    account_body=@utf8.encode(body),
  )
  let crypto = epoch_test_crypto()
  original_selection_fixture(host, "denied-nonce", "denied-original-run")
  |> ignore
  let denied = host.lookup_submitted_run_original_by_id(
    crypto, "operator", "cli", "denied-original-run",
  )
  host.close().unwrap()
  assert_true(denied is Err(Journal(AuthorizationDenied)))
  let other = policy_host_fixture("original-id-foreign")
  original_selection_fixture(other, "foreign-nonce", "foreign-original-run")
  |> ignore
  let principal = other.lookup_submitted_run_original_by_id(
    crypto, "foreign", "cli", "foreign-original-run",
  )
  let connection = other.lookup_submitted_run_original_by_id(
    crypto, "operator", "foreign", "foreign-original-run",
  )
  other.close().unwrap()
  let retired = other.lookup_submitted_run_original_by_id(
    crypto, "operator", "cli", "foreign-original-run",
  )
  assert_true(principal is Err(Journal(AuthorizationDenied)))
  assert_true(connection is Err(Journal(AuthorizationDenied)))
  assert_true(retired is Err(Journal(AuthorizationDenied)))
}

///|
test "original Run ID scans all original rows and refuses ambiguous same-ID admissions" {
  let host = policy_host_fixture("original-id-ambiguous")
  let crypto = epoch_test_crypto()
  original_selection_fixture(host, "first-nonce", "same-run-id") |> ignore
  original_selection_fixture(host, "second-nonce", "same-run-id") |> ignore
  let ambiguous = host.lookup_submitted_run_original_by_id(
    crypto, "operator", "cli", "same-run-id",
  )
  host.close().unwrap()
  assert_true(ambiguous is Err(Journal(ForeignRun)))
}

///|
test "original Run ID does not bypass malformed unselected history" {
  let host = policy_host_fixture("original-id-malformed")
  let crypto = epoch_test_crypto()
  original_selection_fixture(host, "first-valid", "valid-selected-run")
  |> ignore
  let (other, _, _) = original_selection_fixture(
    host, "second-corrupt", "unselected-run",
  )
  let journal = host.run_journal().unwrap()
  let original = journal.retained_submission(other).unwrap().unwrap()
  let row = journal.database
    .read("client_submitted_intents", original.reference.request_id)
    .unwrap()
  journal
  .transaction(() => {
    journal.database
    .compare_exchange(
      "client_submitted_intents",
      other.request_id,
      row.revision,
      b"{}",
    )
    .map_err(issue => NativeClientRunJournalIssue::Physical(issue))
  })
  .unwrap()
  |> ignore
  let malformed = host.lookup_submitted_run_original_by_id(
    crypto, "operator", "cli", "valid-selected-run",
  )
  host.close().unwrap()
  assert_true(malformed is Err(Journal(CustodyLost)))
}

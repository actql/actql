///|
fn submitted_run_admission_body(
  admission : NativeClientSubmittedRunAdmission,
) -> Result[String, NativeClientRunJournalIssue] {
  @host.client_submitted_run_admission_wire(
    admission.request,
    admission.run_definition_cid,
    admission.revision,
  ).map_err(issue => {
    match issue {
      @host.Encoding => Encoding
      @host.CustodyLost => CustodyLost
    }
  })
}

///|
fn read_submitted_run_admission(
  wire : String,
) -> Result[NativeClientSubmittedRunAdmission, NativeClientRunJournalIssue] {
  @host.admit_client_submitted_run_admission_wire(wire)
  .map(value => {
    request: value.0,
    run_definition_cid: value.1,
    revision: value.2,
  })
  .map_err(issue => {
    match issue {
      @host.Encoding => Encoding
      @host.CustodyLost => CustodyLost
    }
  })
}

///|
fn submitted_run_test_input(
  reference : NativeClientSubmissionReference,
  run_id : String,
) -> (
  @host.ClientSubmittedIntent,
  NativeClientSubmittedPreparation,
  @host.ClientRequestIdentity,
  @host.ClientCompiledRun,
  @publication.PublicationContract,
) raise {
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
    fail("ordinary original input was not prepared")
  }
  let (request, _, compiled, definition) = journal_test_prepared_run(
    prepared,
    reference.request_id,
    run_id,
  )
  (intent, preparation, request, compiled, definition)
}

///|
test "Native original Run admission retains exact revisions and refuses numeric or malformed text" {
  let (request, _, _, definition) = journal_test_run(
    "revision-request", "revision-run",
  )
  for revision in [0L, 9007199254740993L, 9223372036854775807L] {
    let admission : NativeClientSubmittedRunAdmission = {
      request,
      run_definition_cid: @publication.publication_contract_identity(definition),
      revision,
    }
    let wire = submitted_run_admission_body(admission).unwrap()
    assert_eq(read_submitted_run_admission(wire).unwrap().revision, revision)
    assert_true(
      read_submitted_run_admission(
        wire.replace(
          old="\"admitted_revision\":\"" + revision.to_string() + "\"",
          new="\"admitted_revision\":" + revision.to_string(),
        ),
      )
      is Err(CustodyLost),
    )
  }
  let wire = submitted_run_admission_body({
    request,
    run_definition_cid: @publication.publication_contract_identity(definition),
    revision: 0L,
  }).unwrap()
  for malformed in ["-1", "00", "9223372036854775808"] {
    assert_true(
      read_submitted_run_admission(
        wire.replace(
          old="\"admitted_revision\":\"0\"",
          new="\"admitted_revision\":\"" + malformed + "\"",
        ),
      )
      is Err(CustodyLost),
    )
  }
}

///|
test "Native original Submission and Run acceptance are atomic immutable and recoverable" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "client-submitted-run-reopen",
  )
  let scope = "sha256:" + "a".repeat(64)
  let (intent, preparation, request, compiled, definition) = submitted_run_test_input(
    reference, "original-run",
  )
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  let record = journal
    .accept_submitted_run(
      authority, reference, preparation, request, compiled, definition, scope, true,
      1002.0,
    )
    .unwrap()
  guard native_client_submitted_run_admission(record) is Some(admission) else {
    fail("original Run admission was not retained")
  }
  assert_eq(
    native_client_submitted_run_definition_cid(admission),
    @publication.publication_contract_identity(definition),
  )
  assert_eq(native_client_submitted_run_admission_revision(admission), 0L)
  guard journal.lookup(request, true) is Ok(Retained(run)) else {
    fail("original Run binding missing")
  }
  assert_false(run.dispatch_reserved)
  assert_false(run.physical_start_claimed)
  assert_eq(run_journal_custody(database, 8).unwrap().0, 1)
  assert_eq(journal.submitted_intent_custody().unwrap().0, 1)
  let repeated = journal
    .accept_submitted_run(
      authority, reference, preparation, request, compiled, definition, scope, true,
      1003.0,
    )
    .unwrap()
  assert_eq(repeated.revision, record.revision)
  // A later control revision cannot overwrite the immutable acceptance fact.
  journal.reserve_dispatch(request, true).unwrap() |> ignore
  database.close_checked().unwrap()
  let database = epoch_test_database("client-submitted-run-reopen")
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let authority = open_native_client_epoch_authority(
    database,
    epoch_test_crypto(),
    100.0,
  ).unwrap()
  let reference = admit_native_client_submission_reference(reference.wire).unwrap()
  guard journal.lookup_submitted_intent(
      authority, reference, scope, true, 1100.0,
    )
    is Ok(Submitted(restored)) &&
    native_client_submitted_run_admission(restored) is Some(admission) else {
    fail("expired original reference lost its accepted Run")
  }
  assert_eq(
    native_client_submitted_run_definition_cid(admission),
    @publication.publication_contract_identity(definition),
  )
  assert_eq(admission.revision, 0L)
  let original_request = native_client_submitted_run_request(admission)
  guard journal.lookup(original_request, true) is Ok(Retained(run)) else {
    fail("restored original Run is unavailable")
  }
  assert_eq(run.revision, 1L)
  assert_true(run.dispatch_reserved)
  assert_false(run.physical_start_claimed)
  assert_eq(run_journal_custody(database, 8).unwrap().0, 1)
  database.close_checked().unwrap()
}

///|
test "Native original Run acceptance refuses changed intent foreign owners and references" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "client-submitted-run-refusals",
  )
  let scope = "sha256:" + "a".repeat(64)
  let (intent, preparation, request, compiled, definition) = submitted_run_test_input(
    reference, "original-run",
  )
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  assert_true(
    journal.accept_submitted_run(
      authority, reference, preparation, request, compiled, definition, scope, false,
      1002.0,
    )
    is Err(AuthorizationDenied),
  )
  let foreign = prepare_native_client_submission_reference(
    reference.epoch,
    "different-submit",
  ).unwrap()
  assert_true(
    journal.accept_submitted_run(
      authority, foreign, preparation, request, compiled, definition, scope, true,
      1002.0,
    )
    is Err(InvalidSubmission),
  )
  // Equal semantic CIDs are insufficient: the existing compilation must retain
  // the exact preparation owner, not an independently reconstructed handle.
  let (_, _, foreign_compiled, _) = journal_test_run(
    reference.request_id,
    "original-run",
  )
  assert_true(
    journal.accept_submitted_run(
      authority, reference, preparation, request, foreign_compiled, definition, scope,
      true, 1002.0,
    )
    is Err(ChangedIntent),
  )
  let changed_intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    preparation_values_document().replace(old="{\"id\":1}", new="{\"id\":3}") +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let changed_preparation = submitted_prepare(changed_intent).unwrap()
  guard changed_preparation.preparation is Computation(changed) else {
    fail("changed original was not prepared")
  }
  let (changed_request, _, changed_compiled, changed_definition) = journal_test_prepared_run(
    changed,
    reference.request_id,
    "changed-run",
  )
  assert_true(
    journal.accept_submitted_run(
      authority, reference, changed_preparation, changed_request, changed_compiled,
      changed_definition, scope, true, 1002.0,
    )
    is Err(ChangedIntent),
  )
  assert_eq(run_journal_custody(database, 8).unwrap().0, 0)
  guard journal.lookup_submitted_intent(
      authority, reference, scope, true, 1003.0,
    )
    is Ok(Submitted(original)) else {
    fail("refusal changed original intent")
  }
  assert_true(original.run_admission is None)
  journal
  .accept_submitted_run(
    authority, reference, preparation, request, compiled, definition, scope, true,
    1004.0,
  )
  .unwrap()
  |> ignore
  let other_definition = @host.issue_client_compiled_run_definition(
    compiled, "local-test", "replacement-run", "2026-10-10T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(
    journal.accept_submitted_run(
      authority, reference, preparation, request, compiled, other_definition, scope,
      true, 1005.0,
    )
    is Err(ForeignRun),
  )
  assert_eq(run_journal_custody(database, 8).unwrap().0, 1)
  database.close_checked().unwrap()
}

///|
test "Native original Run acceptance separates commit loss and reply loss without partial binding" {
  for reply_lost in [false, true] {
    let name = "client-submitted-run-unknown-" + reply_lost.to_string()
    let (database, journal, authority, reference) = submitted_test_setup(name)
    let scope = "sha256:" + "a".repeat(64)
    let (intent, preparation, request, compiled, definition) = submitted_run_test_input(
      reference, "original-run",
    )
    journal
    .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
    .unwrap()
    |> ignore
    submitted_test_fail_commit_after(database, 1, reply_lost)
    assert_true(
      journal.accept_submitted_run(
        authority, reference, preparation, request, compiled, definition, scope,
        true, 1002.0,
      )
      is Err(TransactionUnknown),
    )
    assert_true(database.transaction_fenced())
    if !reply_lost {
      database.rollback().unwrap()
    }
    database.close_checked().unwrap()
    let database = epoch_test_database(name)
    let journal = open_native_client_run_journal(database, 8).unwrap()
    let authority = open_native_client_epoch_authority(
      database,
      epoch_test_crypto(),
      100.0,
    ).unwrap()
    let reference = admit_native_client_submission_reference(reference.wire).unwrap()
    guard journal.lookup_submitted_intent(
        authority, reference, scope, true, 1003.0,
      )
      is Ok(Submitted(original)) else {
      fail("original Submission disappeared at atomic Run acceptance")
    }
    if reply_lost {
      guard original.run_admission is Some(admission) else {
        fail("committed Run admission missing after lost reply")
      }
      assert_eq(
        admission.run_definition_cid,
        @publication.publication_contract_identity(definition),
      )
      guard journal.lookup(admission.request, true) is Ok(Retained(run)) else {
        fail("committed Run missing")
      }
      assert_false(run.dispatch_reserved)
      assert_false(run.physical_start_claimed)
      assert_eq(run_journal_custody(database, 8).unwrap().0, 1)
    } else {
      assert_true(original.run_admission is None)
      assert_true(journal.lookup(request, true) is Ok(UnresolvedHistory))
      assert_eq(run_journal_custody(database, 8).unwrap().0, 0)
    }
    assert_eq(journal.submitted_intent_custody().unwrap().0, 1)
    database.close_checked().unwrap()
  }
}

///|
test "Native original Run acceptance refuses absent intent and capacity without issuing a Run" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "client-submitted-run-capacity",
    max_records=1,
  )
  let scope = "sha256:" + "a".repeat(64)
  let (intent, preparation, request, compiled, definition) = submitted_run_test_input(
    reference, "original-run",
  )
  assert_true(
    journal.accept_submitted_run(
      authority, reference, preparation, request, compiled, definition, scope, true,
      1001.0,
    )
    is Err(CustodyLost),
  )
  assert_eq(run_journal_custody(database, 1).unwrap().0, 0)
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1002.0)
  .unwrap()
  |> ignore
  let (other_request, other_prepared, other_compiled, other_definition) = journal_test_run(
    "unrelated-request", "unrelated-run",
  )
  journal
  .bind_run(
    other_request, other_prepared, other_compiled, other_definition, true,
  )
  .unwrap()
  |> ignore
  assert_true(
    journal.accept_submitted_run(
      authority, reference, preparation, request, compiled, definition, scope, true,
      1003.0,
    )
    is Err(CapacityExceeded),
  )
  guard journal.lookup_submitted_intent(
      authority, reference, scope, true, 1004.0,
    )
    is Ok(Submitted(original)) else {
    fail("capacity refusal removed original intent")
  }
  assert_true(original.run_admission is None)
  assert_eq(run_journal_custody(database, 1).unwrap().0, 1)
  assert_true(journal.lookup(request, true) is Ok(UnresolvedHistory))
  database.close_checked().unwrap()
}

///|
test "Native original accepted Run rejects altered admission custody without repair" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "client-submitted-run-custody",
  )
  let scope = "sha256:" + "a".repeat(64)
  let (intent, preparation, request, compiled, definition) = submitted_run_test_input(
    reference, "original-run",
  )
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  journal
  .accept_submitted_run(
    authority, reference, preparation, request, compiled, definition, scope, true,
    1002.0,
  )
  .unwrap()
  |> ignore
  let original = database
    .read("client_submitted_intents", reference.request_id)
    .unwrap()
  let altered = @utf8.decode(original.body).replace(
    old=@publication.publication_contract_identity(definition),
    new="sha256:" + "f".repeat(64),
  )
  database
  .compare_exchange(
    "client_submitted_intents",
    reference.request_id,
    original.revision,
    @utf8.encode(altered),
  )
  .unwrap()
  |> ignore
  assert_true(
    journal.lookup_submitted_intent(authority, reference, scope, true, 1003.0)
    is Err(CustodyLost),
  )
  assert_true(
    journal.accept_submitted_run(
      authority, reference, preparation, request, compiled, definition, scope, true,
      1004.0,
    )
    is Err(CustodyLost),
  )
  assert_eq(
    database.read("client_submitted_intents", reference.request_id).unwrap().body,
    @utf8.encode(altered),
  )
  assert_eq(run_journal_custody(database, 8).unwrap().0, 1)
  database.close_checked().unwrap()
}

///|
#borrow(database, namespace_bytes, key)
extern "C" fn submitted_test_remove_record(
  database : @sqlite.Database,
  namespace_bytes : Bytes,
  namespace_length : Int,
  key : Bytes,
  key_length : Int,
) -> Bool = "actql_native_sqlite_test_remove_journal_record"

///|
fn submitted_test_setup(
  name : String,
  max_records? : Int = 8,
) -> (
  @sqlite.Database,
  NativeClientRunJournal,
  NativeClientEpochAuthority,
  NativeClientSubmissionReference,
) {
  let database = epoch_test_database(name)
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  initialize_native_client_run_journal(database).unwrap()
  initialize_native_client_submitted_intents(database).unwrap()
  let journal = open_native_client_run_journal(database, max_records).unwrap()
  let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
  let epoch = authority
    .issue_epoch("sha256:" + "a".repeat(64), true, 1000.0)
    .unwrap()
  let reference = prepare_native_client_submission_reference(
    epoch, "original-submit",
  ).unwrap()
  (database, journal, authority, reference)
}

///|
#borrow(database)
extern "C" fn submitted_test_fail_commit_after(
  database : @sqlite.Database,
  skip : Int,
  reply_lost : Bool,
) -> Unit = "actql_native_sqlite_test_fail_commit_after"

///|
test "Native original Submission commit and reply-loss remain distinct across reopen" {
  for reply_lost in [false, true] {
    let name = "client-submission-commit-" + reply_lost.to_string()
    let (database, journal, authority, reference) = submitted_test_setup(name)
    let scope = "sha256:" + "a".repeat(64)
    let intent = submitted_test_intent("SELECT 1 AS n")
    let wire = reference.wire
    // The first COMMIT persists the epoch watermark, and must succeed. Inject
    // at the following original-intent/count transaction, not by elapsed time.
    submitted_test_fail_commit_after(database, 1, reply_lost)
    assert_true(
      journal.record_submitted_intent(
        authority, reference, intent, scope, true, 1001.0,
      )
      is Err(TransactionUnknown),
    )
    assert_true(database.transaction_fenced())
    assert_true(
      journal.lookup_submitted_intent(authority, reference, scope, true, 1002.0)
      is Err(Epoch(Fenced)),
    )
    assert_true(open_native_client_run_journal(database, 8) is Err(Fenced))
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
    let reference = admit_native_client_submission_reference(wire).unwrap()
    let found = journal
      .lookup_submitted_intent(authority, reference, scope, true, 1002.0)
      .unwrap()
    if reply_lost {
      guard found is Submitted(record) else {
        fail("committed original intent was not recovered")
      }
      assert_eq(
        @host.client_submitted_intent_wire(record.intent),
        "{\"input\":{\"format\":\"sql\",\"text\":\"SELECT 1 AS n\"},\"kind\":\"aql\",\"parameters\":null}",
      )
      assert_eq(journal.submitted_intent_custody().unwrap().0, 1)
    } else {
      assert_true(found is UnresolvedSubmissionHistory)
      assert_eq(journal.submitted_intent_custody().unwrap().0, 0)
    }
    assert_eq(run_journal_custody(database, 8).unwrap().0, 0)
    database.close_checked().unwrap()
  }
}

///|
fn submitted_test_intent(text : String) -> @host.ClientSubmittedIntent {
  @host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"" +
    text +
    "\"},\"parameters\":null}",
    65536,
    65536,
    64,
  ).unwrap()
}

///|
test "Native original Submission preparation custody survives reopen without a Run" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "client-submission-original",
  )
  let scope = "sha256:" + "a".repeat(64)
  let original_wire = "{\"kind\":\"aql\",\"input\":{\"text\":\"SELECT 'e\u{0301}\\r\\n'\",\"format\":\"sql\"},\"parameters\":{\"e\u{0301}\":\"line\\r\\n\",\"é\":\"line\\n\",\"nested\":{\"absent_neighbor\":null}}}"
  let expected_wire = "{\"input\":{\"format\":\"sql\",\"text\":\"SELECT 'e\u{0301}\\r\\n'\"},\"kind\":\"aql\",\"parameters\":{\"e\u{0301}\":\"line\\r\\n\",\"nested\":{\"absent_neighbor\":null},\"é\":\"line\\n\"}}"
  let original = @host.prepare_client_submitted_intent(
    original_wire, 65536, 65536, 64,
  ).unwrap()
  assert_eq(@host.client_submitted_intent_wire(original), expected_wire)
  assert_true(
    journal.lookup_submitted_intent(authority, reference, scope, true, 1001.0)
    is Ok(UnresolvedSubmissionHistory),
  )
  let record = journal
    .record_submitted_intent(
      authority, reference, original, scope, true, 1001.0,
    )
    .unwrap()
  assert_eq(@host.client_submitted_intent_wire(record.intent), expected_wire)
  let again = journal
    .record_submitted_intent(
      authority, reference, original, scope, true, 1002.0,
    )
    .unwrap()
  assert_eq(again.revision, record.revision)
  assert_eq(journal.submitted_intent_custody().unwrap().0, 1)
  assert_eq(run_journal_custody(database, 8).unwrap().0, 0)
  let wire = native_client_submission_reference_wire(reference)
  database.close_checked().unwrap()
  let database = epoch_test_database("client-submission-original")
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let authority = open_native_client_epoch_authority(
    database,
    epoch_test_crypto(),
    100.0,
  ).unwrap()
  let reference = admit_native_client_submission_reference(wire).unwrap()
  guard journal.lookup_submitted_intent(
      authority, reference, scope, true, 1100.0,
    )
    is Ok(Submitted(restored)) else {
    fail("original expired reference did not recover its preparing custody")
  }
  assert_eq(@host.client_submitted_intent_wire(restored.intent), expected_wire)
  assert_eq(restored.revision, record.revision)
  // No new admission or provider is implied by authenticated lookup. Expired
  // replay may return the original intent; a different nonce cannot admit it.
  assert_true(
    journal.record_submitted_intent(
      authority, reference, original, scope, true, 1001.0,
    )
    is Ok(_),
  )
  let new_reference = prepare_native_client_submission_reference(
    reference.epoch,
    "new-submit",
  ).unwrap()
  assert_true(
    journal.record_submitted_intent(
      authority, new_reference, original, scope, true, 1001.0,
    )
    is Err(SubmissionEpochRejected(@scope.Expired)),
  )
  assert_eq(run_journal_custody(database, 8).unwrap().0, 0)
  database.close_checked().unwrap()
}

///|
test "Native original Submission rejects changed intent scope token and foreign custody" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "client-submission-conflicts",
  )
  let scope = "sha256:" + "a".repeat(64)
  let original = submitted_test_intent("SELECT 1 AS n")
  journal
  .record_submitted_intent(authority, reference, original, scope, true, 1001.0)
  .unwrap()
  |> ignore
  assert_true(
    journal.record_submitted_intent(
      authority,
      reference,
      submitted_test_intent("SELECT 2 AS n"),
      scope,
      true,
      1002.0,
    )
    is Err(ChangedIntent),
  )
  assert_true(
    journal.lookup_submitted_intent(authority, reference, scope, false, 1002.0)
    is Err(AuthorizationDenied),
  )
  assert_true(
    journal.lookup_submitted_intent(
      authority,
      reference,
      "sha256:" + "b".repeat(64),
      true,
      1002.0,
    )
    is Err(Epoch(ScopeMismatch)),
  )
  let altered = admit_native_client_submission_reference(
    reference.wire.replace(old=scope, new="sha256:" + "b".repeat(64)),
  ).unwrap()
  assert_true(
    journal.lookup_submitted_intent(
      authority,
      altered,
      "sha256:" + "b".repeat(64),
      true,
      1002.0,
    )
    is Err(Epoch(Unverifiable)),
  )
  let (other, _, other_authority, _) = submitted_test_setup(
    "client-submission-other-host",
  )
  assert_true(
    journal.lookup_submitted_intent(
      other_authority, reference, scope, true, 1002.0,
    )
    is Err(InvalidSubmission),
  )
  assert_eq(journal.submitted_intent_custody().unwrap().0, 1)
  assert_eq(run_journal_custody(database, 8).unwrap().0, 0)
  other.close_checked().unwrap()
  database.close_checked().unwrap()
}

///|
test "Native original Submission has explicit finite custody and never repairs missing records" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "client-submission-capacity",
    max_records=1,
  )
  let scope = "sha256:" + "a".repeat(64)
  let original = submitted_test_intent("SELECT 1 AS n")
  journal
  .record_submitted_intent(authority, reference, original, scope, true, 1001.0)
  .unwrap()
  |> ignore
  let another = prepare_native_client_submission_reference(
    reference.epoch,
    "another-submit",
  ).unwrap()
  assert_true(
    journal.record_submitted_intent(
      authority, another, original, scope, true, 1002.0,
    )
    is Err(CapacityExceeded),
  )
  let issuance = database
    .read("client_submitted_intent_custody", "issued")
    .unwrap()
  let usage = database
    .read("client_submitted_intent_usage", "retained")
    .unwrap()
  let namespace_bytes = @utf8.encode("client_submitted_intents")
  let key = @utf8.encode(reference.request_id)
  assert_true(
    submitted_test_remove_record(
      database,
      namespace_bytes,
      namespace_bytes.length(),
      key,
      key.length(),
    ),
  )
  assert_true(
    journal.lookup_submitted_intent(authority, reference, scope, true, 1003.0)
    is Ok(UnresolvedSubmissionHistory),
  )
  assert_true(
    journal.record_submitted_intent(
      authority, reference, original, scope, true, 1003.0,
    )
    is Err(CapacityExceeded),
  )
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/client-submission-capacity.sqlite3"
  assert_true(
    inspect_native_client_state(library, path, 65536L, 1048576L, 1)
    is Err(Custody(Submission(CustodyLost))),
  )
  assert_eq(
    database.read("client_submitted_intent_custody", "issued").unwrap().body,
    b"1",
  )
  let unchanged_issuance = database
    .read("client_submitted_intent_custody", "issued")
    .unwrap()
  let unchanged_usage = database
    .read("client_submitted_intent_usage", "retained")
    .unwrap()
  assert_eq(unchanged_issuance.body, issuance.body)
  assert_eq(unchanged_issuance.revision, issuance.revision)
  assert_eq(unchanged_usage.body, usage.body)
  assert_eq(unchanged_usage.revision, usage.revision)
  assert_true(
    database.read("client_submitted_intents", reference.request_id)
    is Err(@sqlite.NotFound),
  )
  database.close_checked().unwrap()
}

///|
test "Native original Submission rejects malformed references and preserves typed nonce identity" {
  let (database, _, _, reference) = submitted_test_setup(
    "client-submission-reference",
  )
  assert_true(
    prepare_native_client_submission_reference(reference.epoch, "")
    is Err(InvalidSubmission),
  )
  for
    wire in [
      "null",
      "{}",
      "{\"epoch\":null,\"nonce\":\"original-submit\"}",
      reference.wire.replace(old="\"nonce\":", new="\"extra\":false,\"nonce\":"),
    ] {
    assert_true(admit_native_client_submission_reference(wire) is Err(_))
  }
  // Operation nonce is an existing typed identity domain: non-canonical
  // identity text is rejected, never silently converted into another nonce.
  assert_true(
    prepare_native_client_submission_reference(reference.epoch, "e\u{0301}")
    is Err(InvalidSubmission),
  )
  let composed = prepare_native_client_submission_reference(
    reference.epoch,
    "é",
  ).unwrap()
  assert_eq(
    admit_native_client_submission_reference(composed.wire).unwrap().wire,
    composed.wire,
  )
  database.close_checked().unwrap()
}

///|
// A new controlled fixture with the original pre-index rows. This is not an
// old installation replay or an installed physical-pair qualification.
fn journal_append_legacy_fixture(
  name : String,
) -> (
  @sqlite.Database,
  NativeClientRunJournal,
  NativeClientEpochAuthority,
  NativeClientSubmissionReference,
) raise {
  let (database, journal, authority, reference) = submitted_test_setup(name)
  let (intent, preparation, request, compiled, definition) = submitted_run_test_input(
    reference, "legacy-original",
  )
  journal
  .record_submitted_intent(
    authority,
    reference,
    intent,
    "sha256:" + "a".repeat(64),
    true,
    1001.0,
  )
  .unwrap()
  |> ignore
  journal
  .accept_submitted_run(
    authority,
    reference,
    preparation,
    request,
    compiled,
    definition,
    "sha256:" + "a".repeat(64),
    true,
    1002.0,
  )
  .unwrap()
  |> ignore
  database.begin_immediate().unwrap()
  for
    (table, key) in [
      ("client_submitted_intent_usage", "retained"),
      ("client_run_append_coverage", "issued"),
      (
        "client_run_definition_index",
        @publication.publication_contract_identity(definition),
      ),
    ] {
    let original = database.read(table, key).unwrap()
    database.remove_exact(table, key, original.revision, original.body).unwrap()
  }
  database.commit().unwrap()
  assert_eq(
    database
    .lookup_claim_ordinal("client_journal_format", "append-index")
    .unwrap(),
    None,
  )
  (database, journal, authority, reference)
}

///|
test "explicit legacy append migration preserves originals and permits the next new submission" {
  let (database, journal, authority, reference) = journal_append_legacy_fixture(
    "append-legacy-normal-route",
  )
  let original = database
    .read("client_submitted_intents", reference.request_id)
    .unwrap()
  let issued = database
    .read("client_submitted_intent_custody", "issued")
    .unwrap()
  let calls : Array[String] = []
  let access = journal_test_operation_access(database, calls)
  journal
  .transaction_with_reads(
    () => journal.migrate_append_metadata_locked(operations=Some(access)),
    reads=Some(access.reads),
  )
  .unwrap()
  assert_eq(
    database
    .lookup_claim_ordinal("client_journal_format", "append-index")
    .unwrap(),
    Some(1L),
  )
  let same = database
    .read("client_submitted_intents", reference.request_id)
    .unwrap()
  assert_eq(same.body, original.body)
  assert_eq(same.revision, original.revision)
  let same_issued = database
    .read("client_submitted_intent_custody", "issued")
    .unwrap()
  assert_eq(same_issued.body, issued.body)
  assert_eq(same_issued.revision, issued.revision)
  calls.clear()
  journal
  .transaction_with_reads(
    () => journal.migrate_append_metadata_locked(operations=Some(access)),
    reads=Some(access.reads),
  )
  .unwrap()
  assert_false(calls.any(value => value.has_prefix("scan:")))
  let next = prepare_native_client_submission_reference(
    reference.epoch,
    "new-after-migration",
  ).unwrap()
  let (intent, preparation, request, compiled, definition) = submitted_run_test_input(
    next, "new-after-migration",
  )
  journal
  .record_submitted_intent(
    authority,
    next,
    intent,
    "sha256:" + "a".repeat(64),
    true,
    1003.0,
  )
  .unwrap()
  |> ignore
  journal
  .accept_submitted_run(
    authority,
    next,
    preparation,
    request,
    compiled,
    definition,
    "sha256:" + "a".repeat(64),
    true,
    1004.0,
  )
  .unwrap()
  |> ignore
  assert_eq(database.read("client_run_custody", "issued").unwrap().body, b"2")
  assert_eq(
    database.read("client_submitted_intent_custody", "issued").unwrap().body,
    b"2",
  )
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "installed format never recreates deleted append metadata" {
  for
    selected in ["client_submitted_intent_usage", "client_run_append_coverage"] {
    let (database, journal, authority, _) = journal_append_legacy_fixture(
      "append-deleted-" + selected,
    )
    journal.transaction(() => journal.migrate_append_metadata_locked()).unwrap()
    let key = if selected == "client_submitted_intent_usage" {
      "retained"
    } else {
      "issued"
    }
    let row = database.read(selected, key).unwrap()
    database.remove_exact(selected, key, row.revision, row.body).unwrap()
    assert_true(
      journal.transaction(() => journal.migrate_append_metadata_locked())
      is Err(CustodyLost),
    )
    assert_true(database.read(selected, key) is Err(@sqlite.NotFound))
    assert_eq(
      database
      .lookup_claim_ordinal("client_journal_format", "append-index")
      .unwrap(),
      Some(1L),
    )
    database.close_checked().unwrap()
    authority.crypto.close_checked().unwrap()
  }
}

///|
test "legacy migration format-claim refusal rolls back all new metadata" {
  let (database, journal, authority, _) = journal_append_legacy_fixture(
    "append-migration-rollback",
  )
  let calls : Array[String] = []
  let access : NativeClientJournalOperationAccess = {
    ..journal_test_operation_access(database, calls),
    claim_append_format: () => Err(@sqlite.Busy),
  }
  assert_true(
    journal.transaction_with_reads(
      () => journal.migrate_append_metadata_locked(operations=Some(access)),
      reads=Some(access.reads),
    )
    is Err(Physical(@sqlite.Busy)),
  )
  assert_eq(calls[calls.length() - 1], "rollback")
  for
    table in [
      "client_run_append_coverage", "client_run_definition_index", "client_submitted_intent_usage",
    ] {
    assert_true(database.scan_after(table, "") is Err(@sqlite.NotFound))
  }
  assert_eq(
    database
    .lookup_claim_ordinal("client_journal_format", "append-index")
    .unwrap(),
    None,
  )
  assert_eq(database.read("client_run_custody", "issued").unwrap().body, b"1")
  assert_eq(
    database.read("client_submitted_intent_custody", "issued").unwrap().body,
    b"1",
  )
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "legacy migration commit loss keeps its original Unknown and cannot retry the same handle" {
  let (database, journal, authority, _) = journal_append_legacy_fixture(
    "append-migration-unknown",
  )
  submitted_test_fail_commit_after(database, 0, true)
  assert_true(
    journal.transaction(() => journal.migrate_append_metadata_locked())
    is Err(TransactionUnknown),
  )
  assert_true(database.transaction_fenced())
  assert_true(
    journal.transaction(() => journal.migrate_append_metadata_locked())
    is Err(Fenced),
  )
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "ordinary migration entry requires the actual current RunRead decision" {
  let host = local_journal_test_connection("append-migration-denied")
  assert_true(
    host.migrate_journal_append_metadata("operator", "cli")
    is Err(AuthorizationDenied),
  )
  assert_eq(
    host.database
    .lookup_claim_ordinal("client_journal_format", "append-index")
    .unwrap(),
    Some(1L),
  )
  host.close().unwrap()
}

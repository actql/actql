///|
// New controlled prior-format records assembled from the actual epoch and
// existing checked codecs. No old installation, Run or dispatch is replayed.
fn journal_append_legacy_fixture(
  name : String,
) -> (
  @sqlite.Database,
  NativeClientRunJournal,
  NativeClientEpochAuthority,
  NativeClientSubmissionReference,
) raise {
  let database = epoch_test_database(name)
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  initialize_native_client_run_journal_rows(database).unwrap()
  initialize_native_client_submitted_intents(database).unwrap()
  let usage = database
    .read("client_submitted_intent_usage", "retained")
    .unwrap()
  database.begin_immediate().unwrap()
  database
  .remove_exact(
    "client_submitted_intent_usage",
    "retained",
    usage.revision,
    usage.body,
  )
  .unwrap()
  database.commit().unwrap()
  let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
  let epoch = authority
    .issue_epoch("sha256:" + "a".repeat(64), true, 1000.0)
    .unwrap()
  let reference = prepare_native_client_submission_reference(
    epoch, "legacy-submit",
  ).unwrap()
  let (intent, _, request, _, definition) = submitted_run_test_input(
    reference, "legacy-arbitrary-run",
  )
  let record : NativeClientRunRecord = {
    request,
    definition,
    dispatch_reserved: false,
    physical_start_claimed: false,
    cancellation_requested: false,
    publication_binding: None,
    publication_policy_originals: None,
    effect_material_originals: None,
    task_materials_cid: None,
    local_run_policy_originals: None,
    run_observation_originals: None,
    observation_original: None,
    revision: 0L,
    checkpoint: None,
  }
  let run_body = run_record_body(record).unwrap()
  let intent_body = submitted_intent_body(
    reference,
    intent,
    run_admission=Some({
      request,
      run_definition_cid: @publication.publication_contract_identity(definition),
      revision: 0L,
    }),
  ).unwrap()
  database.begin_immediate().unwrap()
  database.compare_exchange("client_run_custody", "issued", 0L, b"1").unwrap()
  |> ignore
  database
  .insert("client_runs", @host.client_request_scope_cid(request), run_body)
  .unwrap()
  |> ignore
  database
  .compare_exchange("client_submitted_intent_custody", "issued", 0L, b"1")
  .unwrap()
  |> ignore
  database
  .insert("client_submitted_intents", reference.request_id, intent_body)
  .unwrap()
  |> ignore
  database.commit().unwrap()
  assert_eq(database.client_run_definition_schema().unwrap(), 0)
  let journal = open_native_client_run_journal(database, 8).unwrap()
  (database, journal, authority, reference)
}

///|
test "explicit legacy migration preserves arbitrary Run and permits the next new submission" {
  let (database, journal, authority, reference) = journal_append_legacy_fixture(
    "append-legacy-normal-route",
  )
  let original = database
    .read("client_submitted_intents", reference.request_id)
    .unwrap()
  let issued = database
    .read("client_submitted_intent_custody", "issued")
    .unwrap()
  let scope = "sha256:" + "a".repeat(64)
  assert_true(
    journal.transaction(() => {
      journal.select_saved_state_run_id_locked(
        authority, scope, "legacy-arbitrary-run",
      )
    })
    is Err(RunIdIndexIncomplete),
  )
  let calls : Array[String] = []
  let access = journal_test_operation_access(database, calls)
  journal
  .transaction_with_reads(
    () => {
      journal.migrate_append_metadata_locked(
        1024L,
        authority,
        "sha256:" + "a".repeat(64),
        operations=Some(access),
      )
    },
    reads=Some(access.reads),
  )
  .unwrap()
  // Locked migration does not publish a process fact before COMMIT. Reopen
  // observes the actual committed original schema, just as a new command does.
  assert_eq(journal.append_schema, 0)
  assert_eq(database.client_run_definition_schema().unwrap(), 1)
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let selected = journal
    .transaction(() => {
      journal.select_saved_state_run_id_locked(
        authority, scope, "legacy-arbitrary-run",
      )
    })
    .unwrap()
    .unwrap()
  assert_eq(selected.0.wire, reference.wire)
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
    () => {
      journal.migrate_append_metadata_locked(
        1024L,
        authority,
        "sha256:" + "a".repeat(64),
        operations=Some(access),
      )
    },
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
test "indexed format never recreates deleted usage metadata" {
  let (database, journal, authority, _) = journal_append_legacy_fixture(
    "append-deleted-usage",
  )
  journal
  .transaction(() => {
    journal.migrate_append_metadata_locked(
      1024L,
      authority,
      "sha256:" + "a".repeat(64),
    )
  })
  .unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let row = database.read("client_submitted_intent_usage", "retained").unwrap()
  database.begin_immediate().unwrap()
  database
  .remove_exact(
    "client_submitted_intent_usage",
    "retained",
    row.revision,
    row.body,
  )
  .unwrap()
  database.commit().unwrap()
  assert_true(
    journal.transaction(() => {
      journal.migrate_append_metadata_locked(
        1024L,
        authority,
        "sha256:" + "a".repeat(64),
      )
    })
    is Err(CustodyLost),
  )
  assert_true(
    database.read("client_submitted_intent_usage", "retained")
    is Err(@sqlite.NotFound),
  )
  assert_eq(database.client_run_definition_schema().unwrap(), 1)
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "legacy migration index refusal rolls back all new metadata" {
  let (database, journal, authority, _) = journal_append_legacy_fixture(
    "append-migration-rollback",
  )
  let calls : Array[String] = []
  let access : NativeClientJournalOperationAccess = {
    ..journal_test_operation_access(database, calls),
    install_run_definition_schema: _ => Err(@sqlite.Busy),
  }
  assert_true(
    journal.transaction_with_reads(
      () => {
        journal.migrate_append_metadata_locked(
          1024L,
          authority,
          "sha256:" + "a".repeat(64),
          operations=Some(access),
        )
      },
      reads=Some(access.reads),
    )
    is Err(Physical(@sqlite.Busy)),
  )
  assert_eq(calls[calls.length() - 1], "rollback")
  assert_true(
    database.scan_after("client_submitted_intent_usage", "")
    is Err(@sqlite.NotFound),
  )
  assert_eq(database.client_run_definition_schema().unwrap(), 0)
  assert_eq(database.read("client_run_custody", "issued").unwrap().body, b"1")
  assert_eq(
    database.read("client_submitted_intent_custody", "issued").unwrap().body,
    b"1",
  )
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "legacy migration commit loss retains Unknown without publishing a format fact" {
  let (database, journal, authority, _) = journal_append_legacy_fixture(
    "append-migration-unknown",
  )
  submitted_test_fail_commit_after(database, 0, true)
  assert_true(
    journal.transaction(() => {
      journal.migrate_append_metadata_locked(
        1024L,
        authority,
        "sha256:" + "a".repeat(64),
      )
    })
    is Err(TransactionUnknown),
  )
  assert_eq(journal.append_schema, 0)
  assert_true(database.transaction_fenced())
  assert_true(
    journal.transaction(() => {
      journal.migrate_append_metadata_locked(
        1024L,
        authority,
        "sha256:" + "a".repeat(64),
      )
    })
    is Err(Fenced),
  )
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "ordinary migration entry requires the actual current RunRead decision" {
  let host = local_journal_test_connection("append-migration-denied")
  assert_true(
    host.migrate_journal_append_metadata("operator", "cli", 1024L)
    is Err(AuthorizationDenied),
  )
  assert_eq(host.database.client_run_definition_schema().unwrap(), 1)
  host.close().unwrap()
}

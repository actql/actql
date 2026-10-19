///|
// Real SQLite acceptance diagnostics. Routing callbacks are not a supplied
// installed pair, authorization issuer or public Run execution qualification.
fn journal_run_operation_fixture(
  name : String,
) -> (
  @sqlite.Database,
  NativeClientRunJournal,
  NativeClientEpochAuthority,
  NativeClientSubmissionReference,
  NativeClientSubmittedPreparation,
  @host.ClientRequestIdentity,
  @host.ClientCompiledRun,
  @publication.PublicationContract,
) raise {
  let (database, journal, authority, reference) = submitted_test_setup(name)
  let (intent, preparation, request, compiled, definition) = submitted_run_test_input(
    reference,
    name + "-run",
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
  (
    database, journal, authority, reference, preparation, request, compiled, definition,
  )
}

///|
test "Run original routing admits one exact Run and observes the same retained admission" {
  let (
    database,
    journal,
    authority,
    reference,
    preparation,
    request,
    compiled,
    definition,
  ) = journal_run_operation_fixture("run-original-route")
  let calls : Array[String] = []
  let access = journal_test_operation_access(database, calls)
  let original = journal
    .accept_submitted_run_with_operations(
      authority,
      reference,
      preparation,
      request,
      compiled,
      definition,
      "sha256:" + "a".repeat(64),
      true,
      1002.0,
      operations=Some(access),
    )
    .unwrap()
  assert_true(original.run_admission is Some(_))
  assert_true(original.run_state_observation is Some((0L, None)))
  assert_true(calls.contains("compare_exchange:client_run_custody:issued"))
  assert_true(
    calls.contains(
      "insert:client_runs:" + @host.client_request_scope_cid(request),
    ),
  )
  assert_true(
    calls.contains(
      "compare_exchange:client_submitted_intents:" + reference.request_id,
    ),
  )
  let issued = database.read("client_run_custody", "issued").unwrap()
  assert_eq(issued.body, b"1")
  let run = database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  assert_false(read_run_record(run).unwrap().physical_start_claimed)
  calls.clear()
  let retained = journal
    .accept_submitted_run_with_operations(
      authority,
      reference,
      preparation,
      request,
      compiled,
      definition,
      "sha256:" + "a".repeat(64),
      true,
      1003.0,
      operations=Some(access),
    )
    .unwrap()
  assert_eq(retained.revision, original.revision)
  assert_false(calls.contains("compare_exchange:client_run_custody:issued"))
  assert_false(
    calls.contains(
      "insert:client_runs:" + @host.client_request_scope_cid(request),
    ),
  )
  assert_false(
    calls.contains(
      "compare_exchange:client_submitted_intents:" + reference.request_id,
    ),
  )
  let after_count = database.read("client_run_custody", "issued").unwrap()
  let after_run = database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  assert_eq(after_count.body, issued.body)
  assert_eq(after_count.revision, issued.revision)
  assert_eq(after_run.body, run.body)
  assert_eq(after_run.revision, run.revision)
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "Run original routing rolls back count Run insert and actual final intent CAS together" {
  let (
    database,
    journal,
    authority,
    reference,
    preparation,
    request,
    compiled,
    definition,
  ) = journal_run_operation_fixture("run-original-rollback")
  let issued = database.read("client_run_custody", "issued").unwrap()
  let intent = database
    .read("client_submitted_intents", reference.request_id)
    .unwrap()
  let calls : Array[String] = []
  let observed = Ref(false)
  let access : NativeClientJournalOperationAccess = {
    ..journal_test_operation_access(database, calls),
    compare_exchange: (table, key, revision, body) => {
      let changed = database.compare_exchange(table, key, revision, body)
      if table == "client_submitted_intents" {
        changed.unwrap() |> ignore
        observed.val = database.read("client_run_custody", "issued").unwrap().body ==
          b"1" &&
          database.read("client_runs", @host.client_request_scope_cid(request))
          is Ok(_)
        Err(@sqlite.Busy)
      } else {
        changed
      }
    },
  }
  assert_true(
    journal.accept_submitted_run_with_operations(
      authority,
      reference,
      preparation,
      request,
      compiled,
      definition,
      "sha256:" + "a".repeat(64),
      true,
      1002.0,
      operations=Some(access),
    )
    is Err(Physical(@sqlite.Busy)),
  )
  assert_true(observed.val)
  assert_eq(calls[calls.length() - 1], "rollback")
  let after_count = database.read("client_run_custody", "issued").unwrap()
  let after_intent = database
    .read("client_submitted_intents", reference.request_id)
    .unwrap()
  assert_eq(after_count.body, issued.body)
  assert_eq(after_count.revision, issued.revision)
  assert_eq(after_intent.body, intent.body)
  assert_eq(after_intent.revision, intent.revision)
  assert_true(
    database.read("client_runs", @host.client_request_scope_cid(request))
    is Err(@sqlite.NotFound),
  )
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "Run original routing retains an actual committed admission after a lost reply and fences retry" {
  let (
    database,
    journal,
    authority,
    reference,
    preparation,
    request,
    compiled,
    definition,
  ) = journal_run_operation_fixture("run-original-unknown")
  let calls : Array[String] = []
  let ordinary = journal_test_read_access(database, calls)
  let commits = Ref(0)
  let reads : NativeClientJournalReadAccess = {
    ..ordinary,
    transaction: operation => {
      if operation is JournalCommit {
        database.commit().unwrap()
        commits.val += 1
        if commits.val == 2 {
          calls.push("admission-commit-lost")
          Err(@sqlite.Busy)
        } else {
          calls.push("clock-commit")
          Ok(())
        }
      } else {
        (ordinary.transaction)(operation)
      }
    },
  }
  let access = { ..journal_test_operation_access(database, calls), reads, }
  assert_true(
    journal.accept_submitted_run_with_operations(
      authority,
      reference,
      preparation,
      request,
      compiled,
      definition,
      "sha256:" + "a".repeat(64),
      true,
      1002.0,
      operations=Some(access),
    )
    is Err(TransactionUnknown),
  )
  assert_eq(commits.val, 2)
  assert_true(journal.fenced)
  assert_true(database.transaction_fenced())
  let run = database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  let intent = database
    .read("client_submitted_intents", reference.request_id)
    .unwrap()
  assert_true(
    @host.decode_client_submitted_journal_row(intent.body).unwrap().run_admission
    is Some(_),
  )
  // The raw committed bytes remain inspectable in this diagnostic. The actual
  // fenced Owner cannot turn them into a new admission or another dispatch.
  assert_false(read_run_record(run).unwrap().physical_start_claimed)
  calls.clear()
  assert_true(
    journal.accept_submitted_run_with_operations(
      authority,
      reference,
      preparation,
      request,
      compiled,
      definition,
      "sha256:" + "a".repeat(64),
      true,
      1003.0,
      operations=Some(access),
    )
    is Err(Epoch(Fenced)),
  )
  assert_false(calls.any(value => value.has_prefix("compare_exchange:")))
  assert_false(calls.any(value => value.has_prefix("insert:")))
  assert_eq(
    database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap().body,
    run.body,
  )
  let after = database
    .read("client_submitted_intents", reference.request_id)
    .unwrap()
  assert_eq(after.body, intent.body)
  assert_eq(after.revision, intent.revision)
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

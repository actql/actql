///|
test "Native retained work current keeps the authenticated original record local" {
  let database = epoch_test_database("retained-current-record")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "retained-current-request", "retained-current-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let start = claim_native_client_retained_work_first_start(journal, request, () => {
    true
  }).unwrap()
  let before = database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  let mut callbacks = 0
  assert_true(
    start.require_current(journal, request, () => {
      callbacks = callbacks + 1
      true
    })
    is Ok(_),
  )
  assert_eq(callbacks, 1)
  let after = database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  assert_eq(after.body, before.body)
  assert_eq(after.revision, before.revision)
  assert_false(journal.claim_physical_start(request, true).unwrap())
  database.close_checked().unwrap()
}

///|
test "Native retained work current observes cancellation performed by its current callback" {
  let database = epoch_test_database("retained-current-cancel")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "retained-cancel-request", "retained-cancel-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let start = claim_native_client_retained_work_first_start(journal, request, () => {
    true
  }).unwrap()
  let outcome = start.require_current(journal, request, () => {
    journal
    .transaction(() => {
      let record = journal.retained(request).unwrap().unwrap()
      journal.save({ ..record, cancellation_requested: true, }).map(_ => ())
    })
    .unwrap()
    true
  })
  assert_true(outcome is Err(NeedsOriginalReconciliation))
  guard journal.lookup(request, true) is Ok(Retained(record)) else {
    fail("Original cancellation missing")
  }
  assert_true(record.cancellation_requested)
  assert_true(record.physical_start_claimed)
  database.close_checked().unwrap()
}

///|
test "Native retained work current never carries Allow into a later predicate" {
  let database = epoch_test_database("retained-current-denied")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "retained-denied-request", "retained-denied-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let start = claim_native_client_retained_work_first_start(journal, request, () => {
    true
  }).unwrap()
  assert_true(start.require_current(journal, request, () => true) is Ok(_))
  assert_true(
    start.require_current(journal, request, () => false)
    is Err(AuthorizationDenied),
  )
  database.close_checked().unwrap()
}

///|
test "Native retained work current rejects a foreign journal before invoking current" {
  let database = epoch_test_database("retained-current-own")
  let foreign_database = epoch_test_database("retained-current-foreign")
  initialize_native_client_run_journal(database).unwrap()
  initialize_native_client_run_journal(foreign_database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let foreign_journal = open_native_client_run_journal(foreign_database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "retained-own-request", "retained-own-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let start = claim_native_client_retained_work_first_start(journal, request, () => {
    true
  }).unwrap()
  let mut callbacks = 0
  assert_true(
    start.require_current(foreign_journal, request, () => {
      callbacks = callbacks + 1
      true
    })
    is Err(Journal(ForeignRun)),
  )
  assert_eq(callbacks, 0)
  database.close_checked().unwrap()
  foreign_database.close_checked().unwrap()
}

///|
test "Native retained work current stays selected while integrity detects malformed other Runs" {
  let database = epoch_test_database("retained-current-nonselected")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "retained-selected-request", "retained-selected-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let start = claim_native_client_retained_work_first_start(journal, request, () => {
    true
  }).unwrap()
  let (other, other_prepared, other_compiled, other_definition) = journal_test_run(
    "retained-other-request", "retained-other-run",
  )
  journal
  .bind_run(other, other_prepared, other_compiled, other_definition, true)
  .unwrap()
  |> ignore
  let key = @host.client_request_scope_cid(other)
  let original = database.read("client_runs", key).unwrap()
  database
  .compare_exchange("client_runs", key, original.revision, b"{}")
  .unwrap()
  |> ignore
  start.require_current(journal, request, () => true).unwrap()
  assert_true(run_journal_custody(database, 8) is Err(CustodyLost))
  let unchanged = database.read("client_runs", key).unwrap()
  assert_eq(unchanged.body, b"{}")
  assert_eq(unchanged.revision, original.revision + 1L)
  database.close_checked().unwrap()
}

///|
test "Native retained work current preserves transaction fences after its callback" {
  let database = epoch_test_database("retained-current-fenced")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "retained-fenced-request", "retained-fenced-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let start = claim_native_client_retained_work_first_start(journal, request, () => {
    true
  }).unwrap()
  assert_true(
    start.require_current(journal, request, () => {
      database.fence_transactions()
      true
    })
    is Err(Journal(Fenced)),
  )
  database.close_checked().unwrap()
}

///|
test "Native retained work current rejects a different original definition after its callback" {
  let database = epoch_test_database("retained-current-definition")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "retained-definition-request", "retained-definition-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let start = claim_native_client_retained_work_first_start(journal, request, () => {
    true
  }).unwrap()
  let (_, _, _, replacement) = journal_test_run(
    "retained-definition-request", "retained-replacement-run",
  )
  assert_true(
    start.require_current(journal, request, () => {
      journal
      .transaction(() => {
        let record = journal.retained(request).unwrap().unwrap()
        journal.save({ ..record, definition: replacement, }).map(_ => ())
      })
      .unwrap()
      true
    })
    is Err(NeedsOriginalReconciliation),
  )
  database.close_checked().unwrap()
}

///|
test "Native retained work current permits a later authenticated control revision" {
  let database = epoch_test_database("retained-current-revision")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "retained-revision-request", "retained-revision-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let start = claim_native_client_retained_work_first_start(journal, request, () => {
    true
  }).unwrap()
  assert_true(
    start.require_current(journal, request, () => {
      journal
      .transaction(() => {
        let record = journal.retained(request).unwrap().unwrap()
        journal.save(record).map(_ => ())
      })
      .unwrap()
      true
    })
    is Ok(_),
  )
  guard journal.lookup(request, true) is Ok(Retained(record)) else {
    fail("Original revised record missing")
  }
  assert_true(record.revision > start.observed_revision)
  assert_eq(
    @publication.publication_contract_identity(record.definition),
    @publication.publication_contract_identity(definition),
  )
  database.close_checked().unwrap()
}

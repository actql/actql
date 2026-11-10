///|
// Actual legacy SQLite and original Common compilation. These checks exercise
// pure correspondence, not installed capacity, permission or physical work.
test "unchanged prepared Run binding survives own row revision but not failure or operation end" {
  let (database, journal, _, _) = submitted_test_setup("prepared-run-once")
  let (request, prepared, compiled, definition) = journal_test_run(
    "prepared-request", "arbitrary-legacy-run-id",
  )
  journal.operation_active = true
  journal
  .validate_prepared_run_binding(request, prepared, compiled, definition)
  .unwrap()
  for _ in 0..<8 {
    journal
    .validate_prepared_run_binding(request, prepared, compiled, definition)
    .unwrap()
  }
  let admitted = @publication.admit_publication_contract(
    "run_definition",
    @publication.publication_contract_json(definition),
    65536,
    4096,
    64,
  ).unwrap()
  // The same verified definition need not retain cross-admission pointers.
  journal
  .validate_prepared_run_binding(request, prepared, compiled, admitted)
  .unwrap()
  let another_request = @host.prepare_source_free_client_request_identity(
    prepared,
    @host.client_request_authority_scope_cid(request),
    "another-request",
  ).unwrap()
  journal
  .validate_prepared_run_binding(another_request, prepared, compiled, admitted)
  .unwrap()
  let record = journal
    .bind_run(request, prepared, compiled, definition, true)
    .unwrap()
  let updated = journal
    .transaction(() => journal.save({ ..record, dispatch_reserved: true, }))
    .unwrap()
  assert_eq(updated.revision, record.revision + 1L)
  journal
  .validate_prepared_run_binding(request, prepared, compiled, definition)
  .unwrap()
  let (_, foreign, _, _) = journal_test_run("foreign-prepared", "foreign-run")
  assert_true(
    journal.validate_prepared_run_binding(
      request, foreign, compiled, definition,
    )
    is Err(ChangedIntent),
  )
  journal
  .validate_prepared_run_binding(request, prepared, compiled, definition)
  .unwrap()
  let changed = @host.issue_client_compiled_run_definition(
    compiled, "local-test", "another-valid-run-id", "2026-10-10T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  journal
  .validate_prepared_run_binding(request, prepared, compiled, changed)
  .unwrap()
  journal.operation_active = false
  journal.invalidate_operation_record()
  // Unscoped callers retain the original validation on each call.
  journal
  .validate_prepared_run_binding(request, prepared, compiled, definition)
  .unwrap()
  journal
  .validate_prepared_run_binding(request, prepared, compiled, definition)
  .unwrap()
  database.close_checked().unwrap()
}

///|
test "rollback retires prepared correspondence and lost commit cannot revive it" {
  let (database, journal, _, _) = submitted_test_setup("prepared-run-return")
  let (request, prepared, compiled, definition) = journal_test_run(
    "prepared-return", "prepared-return-run",
  )
  journal.operation_active = true
  journal
  .validate_prepared_run_binding(request, prepared, compiled, definition)
  .unwrap()
  let refused : Result[Unit, NativeClientRunJournalIssue] = journal.transaction(() => {
      Err(CustodyLost)
    },
  )
  assert_true(refused is Err(CustodyLost))
  journal
  .validate_prepared_run_binding(request, prepared, compiled, definition)
  .unwrap()
  submitted_test_fail_commit_after(database, 0, true)
  assert_true(journal.transaction(() => Ok(())) is Err(TransactionUnknown))
  assert_true(
    journal.validate_prepared_run_binding(
      request, prepared, compiled, definition,
    )
    is Err(Fenced),
  )
  assert_true(database.transaction_fenced())
  journal.operation_active = false
  journal.invalidate_operation_record()
  database.close_checked().unwrap()
}

///|
// Legacy original correspondence regression only; not Source permission,
// installed capacity or actual relation Work execution.
test "relation entry cache guard refuses absent foreign and invalidated original binding" {
  let (database, journal, _, _) = submitted_test_setup("relation-entry-binding")
  let (request, prepared, compiled, definition) = journal_test_run(
    "relation-entry-request", "relation-entry-run",
  )
  assert_false(
    relation_file_prepared_binding_current(
      journal, request, prepared, compiled, definition,
    ),
  )
  journal.operation_active = true
  assert_false(
    relation_file_prepared_binding_current(
      journal, request, prepared, compiled, definition,
    ),
  )
  journal
  .validate_prepared_run_binding(request, prepared, compiled, definition)
  .unwrap()
  assert_true(
    relation_file_prepared_binding_current(
      journal, request, prepared, compiled, definition,
    ),
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  assert_true(
    relation_file_prepared_binding_current(
      journal, request, prepared, compiled, definition,
    ),
  )
  assert_true(journal.lookup(request, true) is Ok(Retained(_)))
  assert_true(
    relation_file_prepared_binding_current(
      journal, request, prepared, compiled, definition,
    ),
  )
  journal.reserve_dispatch(request, true).unwrap() |> ignore
  assert_true(
    relation_file_prepared_binding_current(
      journal, request, prepared, compiled, definition,
    ),
  )
  let start = claim_native_client_retained_work_first_start(journal, request, () => {
    relation_file_prepared_binding_current(
      journal, request, prepared, compiled, definition,
    )
  }).unwrap()
  assert_true(
    relation_file_prepared_binding_current(
      journal, request, prepared, compiled, definition,
    ),
  )
  start
  .require_current(journal, request, () => {
    relation_file_prepared_binding_current(
      journal, request, prepared, compiled, definition,
    )
  })
  .unwrap()
  assert_true(
    relation_file_prepared_binding_current(
      journal, request, prepared, compiled, definition,
    ),
  )
  let (_, foreign, _, _) = journal_test_run(
    "relation-entry-foreign", "relation-entry-foreign-run",
  )
  assert_false(
    relation_file_prepared_binding_current(
      journal, request, foreign, compiled, definition,
    ),
  )
  assert_true(
    relation_file_prepared_binding_current(
      journal, request, prepared, compiled, definition,
    ),
  )
  let refused : Result[Unit, NativeClientRunJournalIssue] = journal.transaction(() => {
      Err(CustodyLost)
    },
  )
  assert_true(refused is Err(CustodyLost))
  assert_false(
    relation_file_prepared_binding_current(
      journal, request, prepared, compiled, definition,
    ),
  )
  journal.operation_active = false
  journal.invalidate_operation_record()
  database.close_checked().unwrap()
}

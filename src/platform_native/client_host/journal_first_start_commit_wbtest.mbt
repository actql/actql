///|
// Journal-owner diagnostic only. These use the existing real SQLite COMMIT
// fault port, not substituted operations or physical Work/StoreReturn ACKs.
fn journal_first_start_commit_failure(reply_lost : Bool) -> Unit raise {
  let name = if reply_lost {
    "journal-first-start-lost-reply"
  } else {
    "journal-first-start-pre-commit"
  }
  let (database, journal, request) = journal_start_operation_fixture(name)
  let key = @host.client_request_scope_cid(request)
  let before = database.read("client_runs", key).unwrap()
  let initial = read_run_record(before).unwrap()
  assert_false(initial.dispatch_reserved)
  assert_false(initial.physical_start_claimed)
  let callbacks = Ref(0)
  // The first real COMMIT is reserve_dispatch. The second is the original
  // physical-start claim. The current callback performs no Journal operation.
  submitted_test_fail_commit_after(database, 1, reply_lost)
  let original = claim_native_client_retained_work_first_start(
    journal,
    request,
    () => {
      callbacks.val += 1
      true
    },
  )
  assert_true(original is Err(Journal(TransactionUnknown)))
  assert_eq(callbacks.val, 2)
  assert_true(journal.fenced)
  assert_true(database.transaction_fenced())
  assert_true(
    claim_native_client_retained_work_first_start(journal, request, () => true)
    is Err(Journal(Fenced)),
  )
  if reply_lost {
    assert_true(
      database.transaction_state() is Ok(@sqlite.NoActiveSqliteTransaction),
    )
  } else {
    assert_true(
      database.transaction_state() is Ok(@sqlite.ActiveSqliteTransaction),
    )
    // The same Database owns this still-active transaction. Rollback releases
    // it only after the original Unknown/fences and replay refusal were seen.
    // It does not clear either fence or reinterpret Unknown as non-execution.
    database.rollback().unwrap()
  }
  assert_true(original is Err(Journal(TransactionUnknown)))
  assert_true(journal.fenced)
  assert_true(database.transaction_fenced())
  assert_true(
    database.transaction_state() is Ok(@sqlite.NoActiveSqliteTransaction),
  )
  let stored = database.read("client_runs", key).unwrap()
  let record = read_run_record(stored).unwrap()
  assert_true(record.dispatch_reserved)
  assert_eq(record.physical_start_claimed, reply_lost)
  let committed_revisions = if reply_lost { 2L } else { 1L }
  assert_eq(stored.revision, before.revision + committed_revisions)
  assert_true(
    claim_native_client_retained_work_first_start(journal, request, () => true)
    is Err(Journal(Fenced)),
  )
  let after = database.read("client_runs", key).unwrap()
  assert_eq(after.body, stored.body)
  assert_eq(after.revision, stored.revision)
  assert_true(original is Err(Journal(TransactionUnknown)))
  assert_true(journal.fenced)
  assert_true(database.transaction_fenced())
  database.close_checked().unwrap()
}

///|
test "Journal first-start pre-COMMIT failure retains Unknown and refuses replay" {
  journal_first_start_commit_failure(false)
}

///|
test "Journal first-start lost COMMIT reply retains the durable claim without a token" {
  journal_first_start_commit_failure(true)
}

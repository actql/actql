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
  guard original
    is Err(Journal(JournalStepFailed(SqlStep(@sqlite.Commit, observed), None))) &&
    observed.result is Err(failure) else {
    fail("first-start must preserve the original COMMIT observation")
  }
  if reply_lost {
    assert_true(failure.reply is @sqlite.SqlReplyLost)
    assert_true(observed.state is Some(Ok(@sqlite.NoActiveSqliteTransaction)))
  } else {
    assert_true(failure.reply is @sqlite.SqlNotIssued)
    assert_true(observed.state is Some(Ok(@sqlite.ActiveSqliteTransaction)))
  }
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
  assert_true(
    original
    is Err(Journal(JournalStepFailed(SqlStep(@sqlite.Commit, _), None))),
  )
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
  assert_true(
    original
    is Err(Journal(JournalStepFailed(SqlStep(@sqlite.Commit, _), None))),
  )
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

///|
#borrow(database)
extern "C" fn journal_test_refuse_rollback(
  database : @sqlite.Database,
  count : Int,
) -> Unit = "actql_native_sqlite_test_fail_rollback"

///|
#borrow(database)
extern "C" fn journal_test_refuse_transaction_state(
  database : @sqlite.Database,
  count : Int,
) -> Unit = "actql_native_sqlite_test_fail_transaction_state"

///|
test "Journal retains its body refusal and the actual rollback refusal on the same connection" {
  let name = "journal-original-body-and-rollback-issues"
  let database = epoch_test_database(name)
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let result : Result[Unit, NativeClientRunJournalIssue] = journal.transaction(() => {
    database.insert("fixture", "original", b"private").unwrap() |> ignore
    journal_test_refuse_rollback(database, 1)
    Err(ChangedIntent)
  })
  guard result
    is Err(
      JournalStepFailed(
        SqlStep(@sqlite.Rollback, observed),
        Some(ChangedIntent)
      )
    ) &&
    observed.result is Err(rollback) else {
    fail("missing body or rollback refusal")
  }
  assert_true(rollback.reply is @sqlite.SqlNotIssued)
  assert_true(observed.state is Some(Ok(@sqlite.ActiveSqliteTransaction)))
  assert_true(journal.transaction(() => Ok(())) is Err(Fenced))
  assert_true(database.transaction_fenced())
  database.close_checked().unwrap()
  let retained = epoch_test_database(name)
  assert_true(retained.read("fixture", "original") is Err(@sqlite.NotFound))
  retained.close_checked().unwrap()
}

///|
test "Journal withholds acknowledgement after confirmed COMMIT with unavailable state" {
  let name = "journal-original-confirmed-with-unavailable-state"
  let database = epoch_test_database(name)
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let result = journal.transaction(() => {
    database.insert("fixture", "original", b"committed").unwrap() |> ignore
    journal_test_refuse_transaction_state(database, 1)
    Ok(())
  })
  guard result
    is Err(JournalStepFailed(SqlStep(@sqlite.Commit, observed), None)) else {
    fail("expected a confirmed step without a state acknowledgement")
  }
  assert_true(observed.result is Ok(_))
  assert_true(observed.state is Some(Err(@sqlite.Physical(_))))
  assert_true(journal.transaction(() => Ok(())) is Err(Fenced))
  assert_true(database.transaction_fenced())
  database.close_checked().unwrap()
  let retained = epoch_test_database(name)
  assert_eq(retained.read("fixture", "original").unwrap().body, b"committed")
  retained.close_checked().unwrap()
}

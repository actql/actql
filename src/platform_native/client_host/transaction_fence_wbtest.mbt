///|
#borrow(database)
extern "C" fn client_test_fail_commit(
  database : @sqlite.Database,
  failures : Int,
) -> Unit = "actql_native_sqlite_test_fail_commit"

///|
#borrow(database)
extern "C" fn client_test_fail_commit_reply(
  database : @sqlite.Database,
  failures : Int,
) -> Unit = "actql_native_sqlite_test_fail_commit_reply"

///|
test "Native epoch commit uncertainty fences the existing Run adapter and rewrapping" {
  for reply_lost in [false, true] {
    let name = "client-shared-epoch-fence-" + reply_lost.to_string()
    let database = epoch_test_database(name)
    let crypto = epoch_test_crypto()
    initialize_native_client_epoch_authority(database, crypto).unwrap()
    initialize_native_client_run_journal(database).unwrap()
    let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
    let journal = open_native_client_run_journal(database, 8).unwrap()
    let (request, prepared, compiled, definition) = journal_test_run(
      "request-one", "run-one",
    )
    journal.bind_run(request, prepared, compiled, definition, true).unwrap()
    |> ignore
    if reply_lost {
      client_test_fail_commit_reply(database, 1)
    } else {
      client_test_fail_commit(database, 1)
    }
    assert_true(
      authority.issue_epoch("sha256:" + "a".repeat(64), true, 1000.0)
      is Err(TransactionUnknown),
    )
    assert_true(database.transaction_fenced())
    assert_true(journal.lookup(request, true) is Err(Fenced))
    assert_true(journal.reserve_dispatch(request, true) is Err(Fenced))
    assert_true(journal.claim_physical_start(request, true) is Err(Fenced))
    assert_true(open_native_client_run_journal(database, 8) is Err(Fenced))
    assert_true(
      open_native_client_epoch_authority(database, crypto, 100.0) is Err(Fenced),
    )
    // Physical rollback/close remains possible, but never resets the fence.
    if !reply_lost {
      database.rollback().unwrap()
    }
    assert_true(database.transaction_fenced())
    database.close_checked().unwrap()
    let reopened = epoch_test_database(name)
    let journal = open_native_client_run_journal(reopened, 8).unwrap()
    guard journal.lookup(request, true) is Ok(Retained(record)) else {
      fail("exact original Run missing")
    }
    assert_false(record.dispatch_reserved)
    assert_false(record.physical_start_claimed)
    assert_eq(
      @publication.publication_contract_identity(record.definition),
      @publication.publication_contract_identity(definition),
    )
    reopened.close_checked().unwrap()
  }
}

///|
test "Native Run commit uncertainty fences epoch operations without erasing the durable start record" {
  for reply_lost in [false, true] {
    let name = "client-shared-run-fence-" + reply_lost.to_string()
    let database = epoch_test_database(name)
    let crypto = epoch_test_crypto()
    initialize_native_client_epoch_authority(database, crypto).unwrap()
    initialize_native_client_run_journal(database).unwrap()
    let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
    let journal = open_native_client_run_journal(database, 8).unwrap()
    let (request, prepared, compiled, definition) = journal_test_run(
      "request-one", "run-one",
    )
    journal.bind_run(request, prepared, compiled, definition, true).unwrap()
    |> ignore
    if reply_lost {
      client_test_fail_commit_reply(database, 1)
    } else {
      client_test_fail_commit(database, 1)
    }
    assert_true(
      journal.reserve_dispatch(request, true) is Err(TransactionUnknown),
    )
    assert_true(
      authority.issue_epoch("sha256:" + "a".repeat(64), true, 1000.0)
      is Err(Fenced),
    )
    assert_true(
      open_native_client_epoch_authority(database, crypto, 100.0) is Err(Fenced),
    )
    assert_true(journal.claim_physical_start(request, true) is Err(Fenced))
    if !reply_lost {
      database.rollback().unwrap()
    }
    assert_true(database.transaction_fenced())
    database.close_checked().unwrap()
    let reopened = epoch_test_database(name)
    let journal = open_native_client_run_journal(reopened, 8).unwrap()
    guard journal.lookup(request, true) is Ok(Retained(record)) else {
      fail("exact original Run missing")
    }
    assert_eq(record.dispatch_reserved, reply_lost)
    assert_false(record.physical_start_claimed)
    assert_eq(
      @publication.publication_contract_identity(record.definition),
      @publication.publication_contract_identity(definition),
    )
    assert_eq(
      journal.reserve_dispatch(request, true).unwrap(),
      if reply_lost {
        @host.ReconcileReservedDispatch
      } else {
        @host.ReserveDispatch
      },
    )
    assert_true(journal.claim_physical_start(request, true).unwrap())
    assert_false(journal.claim_physical_start(request, true).unwrap())
    reopened.close_checked().unwrap()
  }
}

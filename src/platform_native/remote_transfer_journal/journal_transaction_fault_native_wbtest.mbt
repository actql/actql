///|
#borrow(database)
extern "C" fn fail_original_transfer_commit(
  database : @sqlite.Database,
  failures : Int,
) -> Unit = "actql_native_sqlite_test_fail_commit"

///|
#borrow(database)
extern "C" fn fail_original_transfer_rollback(
  database : @sqlite.Database,
  failures : Int,
) -> Unit = "actql_native_sqlite_test_fail_rollback"

///|
test "Native transfer normal lookup and duplicate acceptance refuse a private uncertain row" {
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let path = root + "/transfer-private-admission.sqlite3"
  let request = journal_request(@transfer.DirectStream)
  let journal = open_journal(library, path, 262144L, 1, 4096, 5L).unwrap()
  let same_database : Journal = { ..journal, }

  fail_original_transfer_commit(journal.database, 1)
  fail_original_transfer_rollback(journal.database, 1)
  let acceptance = journal.accept(request)
  let active = journal.database.transaction_state()
  let lookup = journal.require(request)
  let duplicate = same_database.accept(request)
  assert_true(journal.close())
  let independent = open_journal(library, path, 262144L, 1, 4096, 5L).unwrap()
  let durable = independent.require(request)
  assert_true(independent.close())

  guard acceptance is Err(TransactionCommit(failure)) else {
    fail("expected the original uncertain COMMIT")
  }
  assert_true(failure.primary.reply is @sqlite.SqlNotIssued)
  assert_true(failure.outcome is @sqlite.CommitUnknown)
  guard failure.cleanup_failure is Some(cleanup) else {
    fail("expected to retain the rollback refusal")
  }
  guard cleanup.rollback is Some(Err(rollback)) else {
    fail("expected a refused rollback")
  }
  assert_true(rollback.step is @sqlite.Rollback)
  assert_true(rollback.reply is @sqlite.SqlNotIssued)
  assert_true(cleanup.state is Ok(@sqlite.ActiveSqliteTransaction))
  assert_true(active is Ok(@sqlite.ActiveSqliteTransaction))
  assert_true(durable is Err(Physical(@sqlite.NotFound)))
  assert_true(lookup is Err(TransactionFenced))
  assert_true(duplicate is Err(TransactionFenced))
}

///|
#borrow(database)
extern "C" fn lose_original_transfer_commit_reply(
  database : @sqlite.Database,
  failures : Int,
) -> Unit = "actql_native_sqlite_test_fail_commit_reply"

///|
test "Native transfer lost COMMIT reply only admits the exact original recovery observation" {
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let path = root + "/transfer-committed-without-reply.sqlite3"
  let request = journal_request(@transfer.DirectStream)
  let key = @transfer.request_journal_identity(request).unwrap()
  let expected = @transfer.remote_transfer_record_durable_json(
    @transfer.open_record(request),
  ).unwrap()
  let journal = open_journal(library, path, 262144L, 1, 4096, 5L).unwrap()
  lose_original_transfer_commit_reply(journal.database, 1)
  guard journal.accept(request) is Err(TransactionCommit(failure)) else {
    fail("expected the original uncertain COMMIT")
  }
  assert_true(failure.primary.reply is @sqlite.SqlReplyLost)
  assert_true(failure.outcome is @sqlite.CommitUnknown)
  assert_true(failure.cleanup_failure is None)
  assert_true(journal.require(request) is Err(TransactionFenced))
  assert_true(journal.accept(request) is Err(TransactionFenced))
  guard journal.database.prepare_lookup_read()
    is Ok(@sqlite.ReadyLookupRead(child)) else {
    fail("expected one current snapshot from the original Database")
  }
  let found = child
    .read_with_body_limit("remote_transfer", key, 262144L)
    .unwrap()
  assert_eq(found.revision, 0L)
  assert_eq(found.body, journal_bytes(expected))
  child.finish().unwrap()
  assert_true(journal.accept(request) is Err(TransactionFenced))
  assert_true(journal.close())
  let reopened = open_journal(library, path, 262144L, 1, 4096, 5L).unwrap()
  let (kind, record) = reopened.accept(request).unwrap()
  assert_eq(kind, ExistingTransfer)
  assert_eq(@transfer.record_revision(record), 0)
  assert_true(reopened.close())
}

///|
test "Native destination receipt refusal preserves the exact first durable write" {
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let path = root + "/destination-receipt-committed-without-reply.sqlite3"
  let request = journal_request(@transfer.TransferStore)
  let foreign_request = journal_request(@transfer.DirectStream)
  let receipt = @transfer.prepare_destination_receipt(request, "material-a").unwrap()
  let foreign = @transfer.prepare_destination_receipt(
    foreign_request, "material-a",
  ).unwrap()
  let original_cid = @transfer.destination_receipt_cid(receipt)
  let key = @transfer.request_journal_identity(request).unwrap()
  let body = journal_bytes(
    original_cid + "\n" + @transfer.destination_receipt_json(receipt).unwrap(),
  )
  let journal = open_journal(library, path, 262144L, 1, 4096, 5L).unwrap()
  journal.accept(request).unwrap() |> ignore
  assert_true(journal.reserve_destination_holding(request, 5L, 1L).unwrap())
  assert_true(
    journal.commit_destination_receipt(foreign, request)
    is Err(Protocol(@transfer.TransferIdentityMismatch)),
  )
  let verifier = library.open_database(path, 262144L).unwrap()
  assert_true(
    verifier.read("remote_transfer_destination_receipt", key)
    is Err(@sqlite.NotFound),
  )
  assert_false(journal.database.transaction_fenced())

  lose_original_transfer_commit_reply(journal.database, 1)
  guard journal.commit_destination_receipt(receipt, request)
    is Err(TransactionCommit(failure)) else {
    fail("expected a lost reply after the first receipt commit")
  }
  assert_true(failure.primary.reply is @sqlite.SqlReplyLost)
  assert_true(failure.outcome is @sqlite.CommitUnknown)
  assert_true(failure.cleanup_failure is None)
  assert_true(
    journal.inspect_destination_receipt(request) is Err(TransactionFenced),
  )
  assert_true(
    journal.commit_destination_receipt(receipt, request)
    is Err(TransactionFenced),
  )
  assert_true(
    journal.release_destination_holding(request) is Err(TransactionFenced),
  )
  guard journal.database.prepare_lookup_read()
    is Ok(@sqlite.ReadyLookupRead(child)) else {
    fail("expected the original read-only child")
  }
  let found = child
    .read_with_body_limit("remote_transfer_destination_receipt", key, 4096L)
    .unwrap()
  assert_eq(found.revision, 0L)
  assert_eq(found.body, body)
  child.finish().unwrap()
  assert_true(
    journal.release_destination_holding(request) is Err(TransactionFenced),
  )
  assert_true(journal.close())

  let reopened = open_journal(library, path, 262144L, 1, 4096, 5L).unwrap()
  let restored = reopened.inspect_destination_receipt(request).unwrap().unwrap()
  assert_eq(@transfer.destination_receipt_cid(restored), original_cid)
  assert_eq(reopened.destination_capacity_usage().unwrap().reserved_bytes, 5L)
  let matched = reopened.commit_destination_receipt(receipt, request).unwrap()
  assert_eq(@transfer.destination_receipt_cid(matched), original_cid)
  let exact = verifier.read("remote_transfer_destination_receipt", key).unwrap()
  assert_eq(exact.revision, 0L)
  assert_eq(exact.body, body)
  assert_true(reopened.release_destination_holding(request).unwrap())
  assert_eq(reopened.destination_capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(reopened.close())
  verifier.close_checked().unwrap()
}

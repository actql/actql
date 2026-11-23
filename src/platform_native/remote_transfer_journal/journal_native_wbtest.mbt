///|
fn journal_cid(fill : String) -> String {
  "sha256:" + fill.repeat(64)
}

///|
fn journal_manifest() -> @manifest.PhysicalManifest {
  @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    journal_cid("1"),
    journal_cid("2"),
    journal_cid("3"),
    1,
    [journal_cid("a")],
    [5L],
    [1],
    1,
    4096,
    5L,
  ).unwrap()
}

///|
fn journal_request(
  route : @transfer.RemoteTransferRoute,
) -> @transfer.RemoteTransferRequest {
  @transfer.prepare_request(
    "native-coordinator",
    "transfer-1",
    route,
    "source-a",
    1,
    "destination-b",
    2,
    "material-a",
    journal_manifest(),
    5L,
    2000000000000L,
    journal_cid("4"),
    journal_cid("5"),
    journal_cid("6"),
  ).unwrap()
}

///|
test "native Transfer journal rejects conflicting occurrence content" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root + "/transfer-" + @env.now().to_string() + ".sqlite3"
  let first = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  let second = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  let request = journal_request(@transfer.DirectStream)
  let (kind, record) = first.accept(request).unwrap()
  assert_eq(kind, NewTransfer)
  assert_eq(second.accept(request).unwrap().0, ExistingTransfer)
  assert_true(
    second.accept(journal_request(@transfer.TransferStore))
    is Err(StateCollision),
  )
  let start = @transfer.prepare_start(record).unwrap()
  first.commit_transition(start).unwrap()
  assert_eq(@transfer.record_revision(second.require(request).unwrap()), 1)
  first.close() |> ignore
  second.close() |> ignore
}

///|
test "native Transfer journal recovers exact durable state after reopen" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/transfer-reopen-" +
    @env.now().to_string() +
    ".sqlite3"
  let request = journal_request(@transfer.TransferStore)
  let first = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  let (_, record) = first.accept(request).unwrap()
  first.commit_transition(@transfer.prepare_start(record).unwrap()).unwrap()
  first
  .commit_transition(@transfer.prepare_failure(record, false, true).unwrap())
  .unwrap()
  first.close() |> ignore
  let reopened = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  let recovered = reopened.recover_after("").unwrap().unwrap()
  assert_eq(
    recovered_remote_transfer_key(recovered),
    @transfer.request_journal_identity(request).unwrap(),
  )
  assert_eq(
    @transfer.record_projection(recovered_remote_transfer_record(recovered)),
    [2, 3, 2, 0, 0, 1, 0, 0, 0],
  )
  reopened.close() |> ignore
}

///|
test "native Store use journal restores exact download progress" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root + "/store-use-" + @env.now().to_string() + ".sqlite3"
  let request = journal_request(@transfer.TransferStore)
  let first = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  let (_, record) = first.accept_store_use(request, "native-use").unwrap()
  first
  .commit_store_use_transition(
    @transfer.prepare_store_use_start(record).unwrap(),
  )
  .unwrap()
  first
  .commit_store_use_transition(
    @transfer.prepare_store_use_progress(record, 1, 5L).unwrap(),
  )
  .unwrap()
  first.close() |> ignore
  let reopened = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  let store_use = @transfer.prepare_store_use(request, "native-use").unwrap()
  assert_eq(
    @transfer.store_use_record_projection(
      reopened.require_store_use(store_use).unwrap(),
    ),
    ["2", "1", "0", "1", "5", "0", ""],
  )
  reopened.close() |> ignore
}

///|
test "destination request fixes one durable Store use before capacity" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/destination-use-" +
    @env.now().to_string() +
    ".sqlite3"
  let request = journal_request(@transfer.TransferStore)
  let first = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  let second = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  ignore(first.accept(request).unwrap())
  assert_true(first.bind_destination_use(request, "use-a").unwrap())
  assert_false(second.bind_destination_use(request, "use-a").unwrap())
  assert_true(
    second.bind_destination_use(request, "use-b") is Err(StateCollision),
  )
  assert_true(first.reserve_destination_holding(request, 5L, 1L).unwrap())
  assert_eq(second.destination_capacity_usage().unwrap().reserved_bytes, 5L)
  assert_true(second.release_destination_holding(request).unwrap())
  assert_eq(first.destination_capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(first.close())
  assert_true(second.close())
  let reopened = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  assert_false(reopened.bind_destination_use(request, "use-a").unwrap())
  assert_true(
    reopened.bind_destination_use(request, "use-b") is Err(StateCollision),
  )
  assert_true(reopened.close())
}

///|
test "committed destination readers durably block reclaim" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/destination-readers-" +
    @env.now().to_string() +
    ".sqlite3"
  let request = journal_request(@transfer.TransferStore)
  let first = open_journal(
    library,
    database_path,
    262144L,
    1,
    4096,
    5L,
    max_destination_readers=2L,
  ).unwrap()
  let second = open_journal(
    library,
    database_path,
    262144L,
    1,
    4096,
    5L,
    max_destination_readers=2L,
  ).unwrap()
  let (_, record) = first.accept(request).unwrap()
  first.commit_transition(@transfer.prepare_start(record).unwrap()).unwrap()
  first
  .commit_transition(
    @transfer.prepare_source_settled(record, true, true).unwrap(),
  )
  .unwrap()
  first
  .commit_transition(@transfer.prepare_destination_commit(record).unwrap())
  .unwrap()
  let receipt = @transfer.prepare_destination_receipt(
    request, "destination-material-a",
  ).unwrap()
  first.commit_destination_receipt(receipt, request).unwrap() |> ignore
  assert_true(first.reserve_destination_holding(request, 5L, 1L).unwrap())
  assert_true(
    first.validate_destination_reader(request, receipt, "reader-a")
    is Err(RecoveryRequired),
  )
  // Validation neither restores a missing material nor consumes a reader slot.
  assert_eq(first.destination_capacity_usage().unwrap().reserved_bytes, 5L)
  match first.acquire_destination_reader(request, receipt, "reader-a") {
    Ok(value) => assert_true(value)
    Err(UnsupportedTarget) => fail("destination reader target unsupported")
    Err(Closed) => fail("destination reader journal closed")
    Err(CleanupPending) => fail("destination reader journal cleanup pending")
    Err(Physical(_)) => fail("destination reader physical failure")
    Err(TransactionFenced | TransactionCommit(_) | TransactionStop(_, _)) =>
      fail(
        "destination reader unexpectedly requires transaction reconciliation",
      )
    Err(Protocol(_)) => fail("destination reader protocol failure")
    Err(StateCollision) => fail("destination reader state collision")
    Err(RecoveryRequired) => fail("destination reader requires recovery")
    Err(MaterialInUse) => fail("destination reader unexpectedly in use")
  }
  first.validate_destination_reader(request, receipt, "reader-a").unwrap()
  second.validate_destination_reader(request, receipt, "reader-a").unwrap()
  let foreign = @transfer.prepare_destination_receipt(request, "other-material").unwrap()
  assert_true(
    first.validate_destination_reader(request, foreign, "reader-a")
    is Err(StateCollision),
  )
  assert_true(
    first.validate_destination_reader(request, receipt, "absent-reader")
    is Err(RecoveryRequired),
  )
  assert_false(
    second.acquire_destination_reader(request, receipt, "reader-a").unwrap(),
  )
  assert_true(
    second.begin_destination_material_reclaim(request, receipt)
    is Err(MaterialInUse),
  )
  assert_true(
    second.release_destination_reader(request, receipt, "reader-a").unwrap(),
  )
  assert_true(
    first.validate_destination_reader(request, receipt, "reader-a")
    is Err(RecoveryRequired),
  )
  assert_false(
    first.release_destination_reader(request, receipt, "reader-a").unwrap(),
  )
  assert_true(
    first.begin_destination_material_reclaim(request, receipt).unwrap(),
  )
  assert_false(
    second.begin_destination_material_reclaim(request, receipt).unwrap(),
  )
  assert_true(
    first.acquire_destination_reader(request, receipt, "reader-b")
    is Err(RecoveryRequired),
  )
  assert_true(
    first.finish_destination_material_reclaim(request, receipt, false)
    is Err(RecoveryRequired),
  )
  assert_true(
    first.finish_destination_material_reclaim(request, receipt, true).unwrap(),
  )
  assert_false(
    second.finish_destination_material_reclaim(request, receipt, true).unwrap(),
  )
  assert_false(
    first.begin_destination_material_reclaim(request, receipt).unwrap(),
  )
  assert_eq(first.destination_capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(first.close())
  assert_true(second.close())
  let reopened = open_journal(
    library,
    database_path,
    262144L,
    1,
    4096,
    5L,
    max_destination_readers=2L,
  ).unwrap()
  assert_true(
    reopened.validate_destination_reader(request, receipt, "reader-a")
    is Err(RecoveryRequired),
  )
  assert_true(
    reopened.acquire_destination_reader(request, receipt, "reader-c")
    is Err(RecoveryRequired),
  )
  assert_true(reopened.close())
}

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

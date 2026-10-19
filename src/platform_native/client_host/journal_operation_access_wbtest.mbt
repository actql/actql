///|
// Real SQLite routing diagnostics. These callbacks are not an installed
// physical pair or evidence of a supplied business execution.
fn journal_test_operation_access(
  database : @sqlite.Database,
  calls : Array[String],
) -> NativeClientJournalOperationAccess {
  {
    reads: journal_test_read_access(database, calls),
    compare_exchange: (table, key, revision, body) => {
      calls.push("compare_exchange:" + table + ":" + key)
      database.compare_exchange(table, key, revision, body)
    },
  }
}

///|
test "Epoch issue routes the original monotonic transaction and rejects a foreign compare exchange" {
  let database = epoch_test_database("journal-routed-issue")
  let foreign = epoch_test_database("journal-routed-issue-foreign")
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
  let calls : Array[String] = []
  let access = journal_test_operation_access(database, calls)
  let scope = "sha256:" + "a".repeat(64)
  let epoch = authority
    .issue_epoch_with_operations(scope, true, 1000.0, operations=Some(access))
    .unwrap()
  assert_eq(calls, [
    "fenced", "begin", "scan:client_submission_epoch:", "scan:client_submission_epoch:authority",
    "read:client_submission_epoch:authority", "compare_exchange:client_submission_epoch:authority",
    "commit",
  ])
  assert_eq(
    authority.verify_epoch(epoch, scope, true, 1001.0).unwrap(),
    @scope.Admissible,
  )
  calls.clear()
  assert_true(
    compare_exchange_client_journal_value(
      foreign,
      "client_submission_epoch",
      "authority",
      0L,
      b"foreign",
      Some(access),
    )
    is Err(@sqlite.Collision),
  )
  assert_eq(calls, [])
  assert_true(
    foreign.read("client_submission_epoch", "authority")
    is Err(@sqlite.NotFound),
  )
  database.close_checked().unwrap()
  foreign.close_checked().unwrap()
  crypto.close_checked().unwrap()
}

///|
test "Epoch routed commit loss preserves Unknown and fences without replacement issue" {
  let database = epoch_test_database("journal-routed-issue-unknown")
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
  let calls : Array[String] = []
  let ordinary = journal_test_read_access(database, calls)
  let reads : NativeClientJournalReadAccess = {
    ..ordinary,
    transaction: operation => {
      if operation is JournalCommit {
        calls.push("commit-lost")
        database.commit().unwrap()
        Err(@sqlite.Busy)
      } else {
        (ordinary.transaction)(operation)
      }
    },
  }
  let access = { ..journal_test_operation_access(database, calls), reads, }
  let scope = "sha256:" + "a".repeat(64)
  assert_true(
    authority.issue_epoch_with_operations(
      scope,
      true,
      1000.0,
      operations=Some(access),
    )
    is Err(TransactionUnknown),
  )
  assert_true(authority.fenced)
  assert_true(database.transaction_fenced())
  assert_true(calls.length() > 0)
  assert_eq(calls[calls.length() - 1], "fence")
  calls.clear()
  assert_true(
    authority.issue_epoch_with_operations(
      scope,
      true,
      1001.0,
      operations=Some(access),
    )
    is Err(Fenced),
  )
  assert_eq(calls, [])
  database.close_checked().unwrap()
  crypto.close_checked().unwrap()
}

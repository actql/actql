///|
// Actual legacy SQLite/explicit Crypto component counters. These do not
// supply an installed Host/pair or establish ordinary command performance.
test "epoch receipt verification shares the original Journal transaction and never caches rollback" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "epoch-original-receipt-transaction",
  )
  let scope = "sha256:" + "a".repeat(64)
  let calls : Array[String] = []
  let operations = journal_test_operation_access(database, calls)
  authority.begin_operation(false)
  assert_true(
    authority.verify_epoch_in_journal_transaction(
      journal,
      reference.epoch,
      scope,
      true,
      1001.0,
      Some(operations),
    )
    is Err(CustodyLost),
  )
  assert_eq(calls.length(), 0)
  let original = database.read("client_submission_epoch", "authority").unwrap()
  let observed = journal
    .transaction_with_reads(
      () => {
        authority
        .verify_epoch_in_journal_transaction(
          journal,
          reference.epoch,
          scope,
          true,
          1001.0,
          Some(operations),
        )
        .map_err(issue => Epoch(issue))
      },
      reads=Some(operations.reads),
    )
    .unwrap()
  assert_eq(observed, @scope.Admissible)
  assert_eq(calls.filter(call => call == "begin").length(), 1)
  assert_eq(calls.filter(call => call == "commit").length(), 1)
  assert_eq(
    calls
    .filter(call => call == "compare_exchange:client_submission_epoch:authority")
    .length(),
    1,
  )
  assert_true(authority.observed_custody is None)
  let committed = database.read("client_submission_epoch", "authority").unwrap()
  assert_eq(committed.revision, original.revision + 1L)
  calls.clear()
  let rolled : Result[Unit, NativeClientRunJournalIssue] = journal.transaction_with_reads(
    () => {
      match
        authority.verify_epoch_in_journal_transaction(
          journal,
          reference.epoch,
          scope,
          true,
          1100.0,
          Some(operations),
        ) {
        Ok(@scope.Expired) => Err(ChangedIntent)
        Ok(_) => Err(CustodyLost)
        Err(issue) => Err(Epoch(issue))
      }
    },
    reads=Some(operations.reads),
  )
  assert_true(rolled is Err(ChangedIntent))
  assert_eq(calls.filter(call => call == "begin").length(), 1)
  assert_eq(calls.filter(call => call == "rollback").length(), 1)
  assert_false(calls.contains("commit"))
  assert_true(authority.observed_custody is None)
  let after = database.read("client_submission_epoch", "authority").unwrap()
  assert_eq(after.revision, committed.revision)
  assert_eq(after.body, committed.body)
  // A rolled-back future watermark cannot make the retained epoch expire.
  assert_eq(
    authority.verify_epoch(reference.epoch, scope, true, 1002.0).unwrap(),
    @scope.Admissible,
  )
  calls.clear()
  assert_true(
    journal.transaction_with_reads(
      () => {
        authority
        .verify_epoch_in_journal_transaction(
          journal,
          reference.epoch,
          scope,
          false,
          1100.0,
          Some(operations),
        )
        .map_err(issue => Epoch(issue))
      },
      reads=Some(operations.reads),
    )
    is Err(Epoch(AuthorizationDenied)),
  )
  assert_false(calls.any(call => call.has_prefix("compare_exchange:")))
  authority.end_operation()
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
// A real legacy publisher is not the captured Journal's routing original.
// Its public Account permission cannot authorize joining another transaction.
test "publication epoch refuses an unbound publisher and keeps the original fence" {
  let (host, request, definition, store) = local_publisher_fixture(
    "epoch-unbound-publication-publisher", true,
  )
  let publisher = host
    .bind_run_publisher(
      epoch_test_crypto(),
      "operator",
      "cli",
      request,
      definition,
      "epoch-unbound-publication-publisher.run.json",
      store,
    )
    .unwrap()
  let (database, journal, authority, reference) = submitted_test_setup(
    "epoch-unbound-publication-journal",
  )
  let calls : Array[String] = []
  let operations = journal_test_operation_access(database, calls)
  let scope = "sha256:" + "a".repeat(64)
  authority.begin_operation(false)
  let before = database.read("client_submission_epoch", "authority").unwrap()
  let refused = journal
    .transaction_with_reads(
      () => {
        journal.publication_read_locked = true
        let refused = authority.verify_epoch_in_journal_transaction(
          journal,
          reference.epoch,
          scope,
          true,
          1001.0,
          Some(operations),
          publication=Some(publisher),
        )
        journal.publication_read_locked = false
        Ok(refused)
      },
      reads=Some(operations.reads),
    )
    .unwrap()
  assert_true(refused is Err(CustodyLost))
  assert_false(calls.any(call => call.has_prefix("compare_exchange:")))
  let after = database.read("client_submission_epoch", "authority").unwrap()
  assert_eq(before.body, after.body)
  assert_eq(before.revision, after.revision)
  assert_true(publisher.current())
  authority.end_operation()
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
  host.close().unwrap()
  assert_true(store.close().unwrap())
}

///|
test "epoch receipt lost outer commit leaves no reusable watermark observation" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "epoch-original-receipt-commit-unknown",
  )
  let scope = "sha256:" + "a".repeat(64)
  authority.begin_operation(false)
  submitted_test_fail_commit_after(database, 0, true)
  let result = journal.transaction(() => {
    authority
    .verify_epoch_in_journal_transaction(
      journal,
      reference.epoch,
      scope,
      true,
      1001.0,
      None,
    )
    .map_err(issue => Epoch(issue))
  })
  assert_true(result is Err(TransactionUnknown))
  assert_true(journal.fenced)
  assert_true(authority.observed_custody is None)
  assert_true(
    authority.verify_epoch_in_journal_transaction(
      journal,
      reference.epoch,
      scope,
      true,
      1002.0,
      None,
    )
    is Err(CustodyLost),
  )
  authority.end_operation()
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "epoch command reuses its actual custody and authentication without renewing expiry" {
  let database = epoch_test_database("epoch-command-once")
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
  let scope = "sha256:" + "a".repeat(64)
  let epoch = authority.issue_epoch(scope, true, 1000.0).unwrap()
  let row = database.read("client_submission_epoch", "authority").unwrap()
  let calls : Array[String] = []
  let operations = journal_test_operation_access(database, calls)
  authority.begin_operation(false)
  for _ in 0..<8 {
    assert_eq(
      authority
      .verify_epoch_with_operations(
        epoch,
        scope,
        true,
        1000.0,
        operations=Some(operations),
      )
      .unwrap(),
      @scope.Admissible,
    )
  }
  assert_eq(
    calls
    .filter(call => call == "read:client_submission_epoch:authority")
    .length(),
    1,
  )
  assert_eq(calls.filter(call => call == "begin").length(), 1)
  assert_eq(calls.filter(call => call == "commit").length(), 1)
  assert_false(calls.any(call => call.has_prefix("compare_exchange:")))
  assert_eq(authority.authenticated_epochs.length(), 1)
  assert_eq(
    database.read("client_submission_epoch", "authority").unwrap().revision,
    row.revision,
  )
  calls.clear()
  // Advancing actual time still makes the original token expire, performs its
  // one real CAS, and retains that successor only after actual COMMIT.
  assert_eq(
    authority
    .verify_epoch_with_operations(
      epoch,
      scope,
      true,
      1100.0,
      operations=Some(operations),
    )
    .unwrap(),
    @scope.Expired,
  )
  assert_eq(
    calls
    .filter(call => call == "compare_exchange:client_submission_epoch:authority")
    .length(),
    1,
  )
  assert_false(calls.any(call => call.has_prefix("read:")))
  calls.clear()
  assert_eq(
    authority
    .verify_epoch_with_operations(
      epoch,
      scope,
      true,
      1001.0,
      operations=Some(operations),
    )
    .unwrap(),
    @scope.Expired,
  )
  assert_false(calls.contains("begin"))
  assert_eq(authority.authenticated_epochs.length(), 1)
  // An immutable MAC result never substitutes for a distinct current decision
  // or a different scope. Deny does no I/O; the next public entry reobserves.
  calls.clear()
  assert_true(
    authority.verify_epoch_with_operations(
      epoch,
      scope,
      false,
      1001.0,
      operations=Some(operations),
    )
    is Err(AuthorizationDenied),
  )
  assert_eq(calls.length(), 0)
  assert_true(
    authority.verify_epoch_with_operations(
      epoch,
      "sha256:" + "b".repeat(64),
      true,
      1001.0,
      operations=Some(operations),
    )
    is Err(ScopeMismatch),
  )
  authority.end_operation()
  assert_true(authority.observed_custody is None)
  assert_eq(authority.authenticated_epochs.length(), 0)
  authority.begin_operation(false)
  calls.clear()
  assert_eq(
    authority
    .verify_epoch_with_operations(
      epoch,
      scope,
      true,
      1001.0,
      operations=Some(operations),
    )
    .unwrap(),
    @scope.Expired,
  )
  assert_eq(
    calls
    .filter(call => call == "read:client_submission_epoch:authority")
    .length(),
    1,
  )
  authority.end_operation()
  database.close_checked().unwrap()
  crypto.close_checked().unwrap()
}

///|
test "epoch cached authentication refuses actual pending Library close" {
  let database = epoch_test_database("epoch-command-library-close")
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
  let scope = "sha256:" + "a".repeat(64)
  let epoch = authority.issue_epoch(scope, true, 1000.0).unwrap()
  let child = crypto.sha256_hasher().unwrap()
  authority.begin_operation(false)
  assert_eq(
    authority.verify_epoch(epoch, scope, true, 1000.0).unwrap(),
    @scope.Admissible,
  )
  assert_eq(authority.authenticated_epochs.length(), 1)
  assert_eq(crypto.close_checked(), Err(@crypto.CleanupPending))
  assert_true(
    authority.verify_epoch(epoch, scope, true, 1000.0) is Err(Crypto(_)),
  )
  assert_true(authority.observed_custody is None)
  assert_eq(authority.authenticated_epochs.length(), 0)
  // Pending/failed lifetime does not revive when this operation is retried;
  // the same child and Library still acknowledge their actual cleanup.
  child.close_checked().unwrap()
  crypto.close_checked().unwrap()
  assert_true(
    authority.verify_epoch(epoch, scope, true, 1000.0) is Err(Crypto(_)),
  )
  authority.end_operation()
  database.close_checked().unwrap()
}

///|
test "epoch failed observation cannot revive cached authentication after key mutation" {
  let database = epoch_test_database("epoch-command-failure")
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
  let scope = "sha256:" + "a".repeat(64)
  let epoch = authority.issue_epoch(scope, true, 1000.0).unwrap()
  let calls : Array[String] = []
  let actual = journal_test_operation_access(database, calls)
  let fail_read = Ref(false)
  let reads = {
    ..actual.reads,
    read: (table, key) => {
      if fail_read.val {
        calls.push("authored read refusal")
        Err(@sqlite.Busy)
      } else {
        (actual.reads.read)(table, key)
      }
    },
  }
  let operations = { ..actual, reads, }
  authority.begin_operation(false)
  authority
  .verify_epoch_with_operations(
    epoch,
    scope,
    true,
    1000.0,
    operations=Some(operations),
  )
  .unwrap()
  |> ignore
  let row = database.read("client_submission_epoch", "authority").unwrap()
  let changed_key = Bytes::make(32, 7)
  database
  .compare_exchange(
    "client_submission_epoch",
    "authority",
    row.revision,
    epoch_custody_body(changed_key, 1000.0).unwrap(),
  )
  .unwrap()
  |> ignore
  authority.invalidate_custody()
  fail_read.val = true
  assert_true(
    authority.verify_epoch_with_operations(
      epoch,
      scope,
      true,
      1000.0,
      operations=Some(operations),
    )
    is Err(Physical(@sqlite.Busy)),
  )
  calls.clear()
  fail_read.val = false
  // Restoring only the authored read port cannot undo its failed observation.
  assert_true(
    authority.verify_epoch_with_operations(
      epoch,
      scope,
      true,
      1000.0,
      operations=Some(operations),
    )
    is Err(Physical(@sqlite.Busy)),
  )
  assert_eq(calls.length(), 0)
  assert_eq(authority.authenticated_epochs.length(), 0)
  authority.end_operation()
  authority.begin_operation(false)
  assert_true(
    authority.verify_epoch_with_operations(
      epoch,
      scope,
      true,
      1000.0,
      operations=Some(operations),
    )
    is Err(Unverifiable),
  )
  assert_eq(
    calls
    .filter(call => call == "read:client_submission_epoch:authority")
    .length(),
    1,
  )
  // A newly issued original under the actual changed key can be used, but it
  // is still a separate token and carries no Account or replacement-Run right.
  let next = authority
    .issue_epoch_with_operations(
      scope,
      true,
      1000.0,
      operations=Some(operations),
    )
    .unwrap()
  assert_eq(
    authority
    .verify_epoch_with_operations(
      next,
      scope,
      true,
      1000.0,
      operations=Some(operations),
    )
    .unwrap(),
    @scope.Admissible,
  )
  authority.end_operation()
  database.close_checked().unwrap()
  crypto.close_checked().unwrap()
}

///|
test "epoch command retains its actual opening observation and never caches a lost watermark commit" {
  let database = epoch_test_database("epoch-command-opening-unknown")
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  let first = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
  let scope = "sha256:" + "a".repeat(64)
  let epoch = first.issue_epoch(scope, true, 1000.0).unwrap()
  let calls : Array[String] = []
  let operations = journal_test_operation_access(database, calls)
  let authority = open_native_client_epoch_authority_with_reads(
    database,
    crypto,
    100.0,
    reads=Some(operations.reads),
  ).unwrap()
  assert_eq(
    calls
    .filter(call => call == "read:client_submission_epoch:authority")
    .length(),
    1,
  )
  calls.clear()
  authority.begin_operation(true)
  assert_eq(
    authority
    .verify_epoch_with_operations(
      epoch,
      scope,
      true,
      1000.0,
      operations=Some(operations),
    )
    .unwrap(),
    @scope.Admissible,
  )
  assert_false(calls.any(call => call.has_prefix("read:") || call == "begin"))
  // A new durable watermark still needs the original COMMIT. A consumed reply
  // stays Unknown even if the database actually committed its write.
  submitted_test_fail_commit_after(database, 0, true)
  assert_true(
    authority.verify_epoch_with_operations(
      epoch,
      scope,
      true,
      1100.0,
      operations=Some(operations),
    )
    is Err(TransactionUnknown),
  )
  assert_true(database.transaction_fenced())
  assert_true(authority.observed_custody is None)
  assert_eq(authority.authenticated_epochs.length(), 0)
  assert_true(
    authority.verify_epoch_with_operations(
      epoch,
      scope,
      true,
      1000.0,
      operations=Some(operations),
    )
    is Err(TransactionUnknown),
  )
  authority.end_operation()
  assert_true(authority.verify_epoch(epoch, scope, true, 1000.0) is Err(Fenced))
  database.close_checked().unwrap()
  crypto.close_checked().unwrap()
}

///|
// Observe routing around real SQLite operations. This fixture supplies no
// installed pair, scope transition, normal profile or permission evidence.
fn journal_test_read_access(
  database : @sqlite.Database,
  calls : Array[String],
) -> NativeClientJournalReadAccess {
  {
    before_submitted_decode: None,
    database,
    fenced: () => {
      calls.push("fenced")
      database.transaction_fenced()
    },
    fence: () => {
      calls.push("fence")
      database.fence_transactions()
    },
    read: (table_name, key) => {
      calls.push("read:" + table_name + ":" + key)
      database.read(table_name, key)
    },
    scan: (table_name, cursor) => {
      calls.push("scan:" + table_name + ":" + cursor)
      database.scan_after(table_name, cursor)
    },
    read_evidence_schema: () => {
      calls.push("read-evidence-schema")
      database.client_read_evidence_schema()
    },
    run_definition_schema: () => {
      calls.push("run-definition-schema")
      database.client_run_definition_schema()
    },
    run_definition_key: definition_cid => {
      calls.push("run-definition-key:" + definition_cid)
      database.client_run_definition_key(definition_cid)
    },
    schema: () => {
      calls.push("schema")
      submission_name_schema_ffi(database)
    },
    _observed_census: () => {
      calls.push("census")
      submission_name_census_ffi(database)
    },
    transaction: operation => {
      match operation {
        JournalBegin => {
          calls.push("begin")
          database.begin_immediate()
        }
        JournalCommit => {
          calls.push("commit")
          database.commit()
        }
        JournalRollback => {
          calls.push("rollback")
          database.rollback()
        }
      }
    },
  }
}

///|
test "original epoch routing preserves query order and the same canonical custody refusal" {
  let database = epoch_test_database("journal-routed-epoch")
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  let expected = read_epoch_custody(database).unwrap()
  let calls : Array[String] = []
  let reads = journal_test_read_access(database, calls)
  assert_eq(read_epoch_custody(database, reads=Some(reads)).unwrap(), expected)
  assert_eq(calls, [
    "scan:client_submission_epoch:", "scan:client_submission_epoch:authority", "read:client_submission_epoch:authority",
  ])
  database.insert("client_submission_epoch", "foreign", b"unexpected").unwrap()
  |> ignore
  calls.clear()
  assert_true(
    read_epoch_custody(database, reads=Some(reads)) is Err(CustodyLost),
  )
  assert_eq(calls, [
    "scan:client_submission_epoch:", "scan:client_submission_epoch:authority",
  ])
  assert_eq(
    database.read("client_submission_epoch", "foreign").unwrap().body,
    b"unexpected",
  )
  database.close_checked().unwrap()
  crypto.close_checked().unwrap()
}

///|
test "original routed custody retains the same accepted Run and intent and rejects missing census rows" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "journal-routed-custody",
  )
  let (intent, preparation, request, compiled, definition) = submitted_run_test_input(
    reference, "routed-original-run",
  )
  let scope = "sha256:" + "a".repeat(64)
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  journal
  .accept_submitted_run(
    authority, reference, preparation, request, compiled, definition, scope, true,
    1002.0,
  )
  .unwrap()
  |> ignore
  let calls : Array[String] = []
  let reads = journal_test_read_access(database, calls)
  assert_true(
    inspect_native_client_custody_rows(database, 8, reads=Some(reads))
    is Ok(Retained),
  )
  assert_true(
    calls.any(value => {
      value == "read:client_runs:" + @host.client_request_scope_cid(request)
    }),
  )
  assert_true(calls.any(value => value == "scan:client_submitted_intents:"))
  assert_eq(run_journal_custody(database, 8, reads=Some(reads)).unwrap().0, 1)
  assert_eq(journal.submitted_intent_custody(reads=Some(reads)).unwrap().0, 1)
  let marker = database.read("client_run_custody", "issued").unwrap()
  database
  .compare_exchange("client_run_custody", "issued", marker.revision, b"2")
  .unwrap()
  |> ignore
  assert_true(
    inspect_native_client_custody_rows(database, 8, reads=Some(reads))
    is Err(Run(CustodyLost)),
  )
  assert_eq(database.read("client_run_custody", "issued").unwrap().body, b"2")
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "original query routing refuses a different physical DB before invoking callbacks" {
  let first = epoch_test_database("journal-query-owner")
  let foreign = epoch_test_database("journal-query-foreign")
  let calls : Array[String] = []
  let reads = journal_test_read_access(first, calls)
  assert_true(
    read_client_journal_value(foreign, "fixture", "original", Some(reads))
    is Err(@sqlite.Collision),
  )
  assert_true(
    scan_client_journal_value(foreign, "fixture", "", Some(reads))
    is Err(@sqlite.Collision),
  )
  assert_true(
    client_journal_transaction_operation(foreign, JournalBegin, Some(reads))
    is Err(@sqlite.Collision),
  )
  assert_eq(read_client_submission_name_schema(foreign, Some(reads)), -1)
  assert_eq(read_client_submission_name_census(foreign, Some(reads)), -1L)
  assert_eq(calls, [])
  first.close_checked().unwrap()
  foreign.close_checked().unwrap()
}

///|
test "original named startup routes its transaction census and HMAC through the same DB" {
  let (database, journal, authority, reference) = named_test_setup(
    "journal-routed-names",
  )
  let intent = submitted_test_intent("SELECT 1 AS n")
  assert_true(
    journal.resolve_or_bind_submitted_name(
      authority,
      "workspace",
      "actor",
      "name",
      intent,
      Some(reference),
      "sha256:" + "a".repeat(64),
      true,
      1001.0,
    )
    is Ok(NamedSubmission(true, _)),
  )
  let calls : Array[String] = []
  let reads = journal_test_read_access(database, calls)
  journal
  .transaction_with_reads(
    () => journal.inspect_submitted_name_startup(authority, reads=Some(reads)),
    reads=Some(reads),
  )
  .unwrap()
  assert_eq(calls[0], "fenced")
  assert_eq(calls[1], "begin")
  assert_eq(calls[calls.length() - 1], "commit")
  assert_true(calls.any(value => value == "schema"))
  assert_true(calls.any(value => value == "census"))
  assert_true(calls.any(value => value == "scan:client_submission_names:"))
  assert_true(
    calls.any(value => value == "read:client_submission_epoch:authority"),
  )
  assert_true(!database.transaction_fenced())
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "phased inspection refusal retains its same pending copy and lock through cleanup" {
  let session = journal_open_original("journal-phased-copy-cleanup")
  let library = local_journal_test_library()
  let borrowed = @filesystem.open_private_root(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap(),
  ).unwrap()
  let inspection = @journal.prepare_sqlite_source_inspection(
    session.state_path + "/client.sqlite3",
    131072L,
    8388608L,
  ).unwrap()
  let database = inspection.open_database(library).unwrap().unwrap()
  local_test_fail_close(database, 2)
  let cleanup_issue = match inspection.close_database() {
    Err(issue) => issue
    Ok(_) => abort("original close fault unexpectedly succeeded")
  }
  // Test-only admission refusal, alongside the actual physical close failure.
  // It is an error payload, never a fabricated resource or custody admission.
  let failure = session.retain_journal_open_failure(
    InspectionPending(
      Some(CustodyLost),
      InspectionCleanup(cleanup_issue),
      inspection,
    ),
  )
  assert_true(failure.retry_cleanup() is Err(_))
  assert_true(inspection.pending())
  match borrowed.acquire_lock_with_custody("local-adoption.lock") {
    Err(original) => original.retry_cleanup().unwrap()
    Ok(lock) => {
      lock.close_checked().unwrap()
      fail("pending inspection copy released the original lock")
    }
  }
  session.parent.private_ownership().unwrap() |> ignore
  failure.retry_cleanup().unwrap()
  assert_false(inspection.pending())
  assert_true(session.parent.private_ownership() is Err(_))
  assert_true(
    failure.issue()
    is InspectionPending(Some(CustodyLost), InspectionCleanup(_), original) &&
    physical_equal(original, inspection),
  )
  failure.retry_cleanup().unwrap()
  let lock = borrowed.acquire_lock_with_custody("local-adoption.lock").unwrap()
  lock.close_checked().unwrap()
  borrowed.close().unwrap()
}

///|
test "original journal open observes the same routed physical fence before custody" {
  let database = epoch_test_database("journal-routed-fence-open")
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  initialize_native_client_run_journal(database).unwrap()
  let calls : Array[String] = []
  let reads = journal_test_read_access(database, calls)
  open_native_client_epoch_authority_with_reads(
    database,
    crypto,
    100.0,
    reads=Some(reads),
  ).unwrap()
  |> ignore
  assert_eq(calls[0], "fenced")
  calls.clear()
  open_native_client_run_journal_with_reads(database, 8, reads=Some(reads)).unwrap()
  |> ignore
  assert_eq(calls[0], "fenced")
  database.fence_transactions()
  calls.clear()
  assert_true(
    open_native_client_epoch_authority_with_reads(
      database,
      crypto,
      100.0,
      reads=Some(reads),
    )
    is Err(Fenced),
  )
  assert_eq(calls, ["fenced"])
  calls.clear()
  assert_true(
    open_native_client_run_journal_with_reads(database, 8, reads=Some(reads))
    is Err(Fenced),
  )
  assert_eq(calls, ["fenced"])
  database.close_checked().unwrap()
  crypto.close_checked().unwrap()
}

///|
test "routed transaction uncertainty fences the same physical DB without resetting it" {
  for reply_lost in [false, true] {
    let database = epoch_test_database(
      "journal-routed-fence-commit-" + reply_lost.to_string(),
    )
    initialize_native_client_run_journal(database).unwrap()
    let journal = open_native_client_run_journal(database, 8).unwrap()
    let calls : Array[String] = []
    let reads = journal_test_read_access(database, calls)
    if reply_lost {
      client_test_fail_commit_reply(database, 1)
    } else {
      client_test_fail_commit(database, 1)
    }
    assert_true(
      journal.transaction_with_reads(() => Ok(()), reads=Some(reads))
      is Err(TransactionUnknown),
    )
    assert_eq(calls[0], "fenced")
    assert_eq(calls[calls.length() - 1], "fence")
    assert_true(database.transaction_fenced())
    calls.clear()
    assert_true(
      open_native_client_run_journal_with_reads(database, 8, reads=Some(reads))
      is Err(Fenced),
    )
    assert_eq(calls, ["fenced"])
    if !reply_lost {
      database.rollback().unwrap()
    }
    assert_true(database.transaction_fenced())
    database.close_checked().unwrap()
  }
}

///|
test "routed fence rejects foreign physical DB before either scalar callback" {
  let database = epoch_test_database("journal-routed-fence-owner")
  let foreign = epoch_test_database("journal-routed-fence-foreign")
  let calls : Array[String] = []
  let reads = journal_test_read_access(database, calls)
  assert_true(client_journal_transaction_fenced(foreign, Some(reads)))
  fence_client_journal_transactions(foreign, Some(reads))
  assert_eq(calls, [])
  assert_true(!database.transaction_fenced())
  assert_true(!foreign.transaction_fenced())
  database.close_checked().unwrap()
  foreign.close_checked().unwrap()
}

///|
fn read_client_submission_name_census(
  database : @sqlite.Database,
  reads : NativeClientJournalReadAccess?,
) -> Int64 {
  match reads {
    None => submission_name_census_ffi(database)
    Some(original) =>
      if physical_equal(database, original.database) {
        (original._observed_census)()
      } else {
        -1L
      }
  }
}

///|
// These callbacks surround actual SQLite operations. They verify private call
// routing and transactions, not an installed pair, phase admission or funding.
fn journal_test_bootstrap_access(
  database : @sqlite.Database,
  calls : Array[String],
  fail_adoption? : Bool = false,
  lose_commit_reply? : Bool = false,
) -> NativeClientJournalBootstrapAccess {
  let reads = journal_test_read_access(database, calls)
  let reads = if lose_commit_reply {
    {
      ..reads,
      transaction: operation => {
        let result = (reads.transaction)(operation)
        match (operation, result) {
          (JournalCommit, Ok(_)) => Err(@sqlite.Physical("lost commit reply"))
          _ => result
        }
      },
    }
  } else {
    reads
  }
  {
    reads,
    install_run_definition_schema: max_rows => {
      calls.push("install run definition schema")
      database.install_client_run_definition_schema(max_rows)
    },
    insert: (table_name, key, body) => {
      calls.push("insert:" + table_name + ":" + key)
      if fail_adoption && table_name == "client_local_adoption" {
        Err(@sqlite.Physical("injected adoption insert failure"))
      } else {
        database.insert(table_name, key, body).map(_ => ())
      }
    },
    capacity: table_name => {
      calls.push("capacity:" + table_name)
      database.capacity_usage(table_name)
    },
    install_names: () => {
      calls.push("install names")
      submission_name_install_ffi(database)
    },
  }
}

///|
test "bootstrap routing retains one original epoch and transaction order" {
  let database = epoch_test_database("bootstrap-routed-original")
  let crypto = epoch_test_crypto()
  let calls : Array[String] = []
  let access = journal_test_bootstrap_access(database, calls)
  initialize_native_local_client_custody(
    database,
    crypto,
    b"original adoption",
    bootstrap=Some(access),
  ).unwrap()
  assert_eq(calls[0], "fenced")
  assert_eq(calls[1], "begin")
  assert_eq(calls[calls.length() - 1], "commit")
  assert_true(calls.contains("install names"))
  assert_true(calls.contains("capacity:client_local_read_evidence"))
  let original_epoch = database
    .read("client_submission_epoch", "authority")
    .unwrap()
  read_epoch_custody(database).unwrap() |> ignore
  assert_eq(
    database.read("client_local_adoption", "adoption").unwrap().body,
    b"original adoption",
  )
  calls.clear()
  assert_true(
    initialize_native_local_client_custody(
      database,
      crypto,
      b"replacement",
      bootstrap=Some(access),
    )
    is Err(CustodyLost),
  )
  assert_eq(calls[calls.length() - 1], "rollback")
  assert_eq(
    database.read("client_submission_epoch", "authority").unwrap().body,
    original_epoch.body,
  )
  database.close_checked().unwrap()
  crypto.close_checked().unwrap()
}

///|
test "bootstrap routed late failure rolls back the same generated originals" {
  let database = epoch_test_database("bootstrap-routed-rollback")
  let crypto = epoch_test_crypto()
  let calls : Array[String] = []
  let access = journal_test_bootstrap_access(
    database,
    calls,
    fail_adoption=true,
  )
  assert_true(
    initialize_native_local_client_custody(
      database,
      crypto,
      b"original adoption",
      bootstrap=Some(access),
    )
    is Err(Physical(@sqlite.Physical("injected adoption insert failure"))),
  )
  assert_true(calls.contains("insert:client_submission_epoch:authority"))
  assert_true(calls.contains("install names"))
  assert_eq(calls[calls.length() - 1], "rollback")
  for
    table_name in [
      "client_submission_epoch", "client_run_custody", "client_local_adoption", "client_submission_name_custody",
    ] {
    assert_true(database.scan_after(table_name, "") is Err(@sqlite.NotFound))
  }
  assert_true(!database.transaction_fenced())
  database.close_checked().unwrap()
  crypto.close_checked().unwrap()
}

///|
test "bootstrap foreign database refuses before original callbacks" {
  let database = epoch_test_database("bootstrap-original-db")
  let foreign = epoch_test_database("bootstrap-foreign-db")
  let calls : Array[String] = []
  let access = Some(journal_test_bootstrap_access(database, calls))
  assert_true(
    insert_bootstrap_journal_value(foreign, "fixture", "key", b"body", access)
    is Err(@sqlite.Collision),
  )
  assert_true(
    bootstrap_journal_capacity_usage(foreign, "fixture", access)
    is Err(@sqlite.Collision),
  )
  assert_true(!install_bootstrap_submission_name_schema(foreign, access))
  assert_eq(calls, [])
  assert_true(database.read("fixture", "key") is Err(@sqlite.NotFound))
  assert_true(foreign.read("fixture", "key") is Err(@sqlite.NotFound))
  database.close_checked().unwrap()
  foreign.close_checked().unwrap()
}

///|
test "bootstrap consumed COMMIT without reply remains fenced and never reissues" {
  let database = epoch_test_database("bootstrap-commit-unknown")
  let crypto = epoch_test_crypto()
  let calls : Array[String] = []
  let access = journal_test_bootstrap_access(
    database,
    calls,
    lose_commit_reply=true,
  )
  assert_true(
    initialize_native_local_client_custody(
      database,
      crypto,
      b"original adoption",
      bootstrap=Some(access),
    )
    is Err(TransactionUnknown),
  )
  assert_eq(calls[calls.length() - 1], "fence")
  assert_true(database.transaction_fenced())
  calls.clear()
  assert_true(
    initialize_native_local_client_custody(
      database,
      crypto,
      b"replacement",
      bootstrap=Some(access),
    )
    is Err(Fenced),
  )
  assert_eq(calls, ["fenced"])
  database.close_checked().unwrap()
  crypto.close_checked().unwrap()
}

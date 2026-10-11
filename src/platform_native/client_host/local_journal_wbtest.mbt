///|
fn local_journal_test_library() -> @sqlite.Library {
  @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
}

///|
fn local_journal_test_connection(name : String) -> NativeLocalHostConnection {
  let (path, source_name, _, _) = local_selected_source(name)
  let crypto = epoch_test_crypto()
  begin_native_local_host_adoption(
    path,
    name + ".host",
    path,
    source_name,
    "operator",
    crypto,
  )
  .unwrap()
  .open_journal(local_journal_test_library(), crypto, 100.0, 8, 8388608L)
  .unwrap()
}

///|
test "Native Local final adoption restores the original epoch and Run custody without new authority" {
  let connected = local_journal_test_connection("local-final-reopen")
  let adoption = connected.adoption_cid()
  let epoch = connected
    .epoch_authority()
    .unwrap()
    .issue_epoch("sha256:" + "a".repeat(64), true, 1000.0)
    .unwrap()
  let epoch_body = connected.database
    .read("client_submission_epoch", "authority")
    .unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "original-request", "original-run",
  )
  connected
  .run_journal()
  .unwrap()
  .bind_run(request, prepared, compiled, definition, true)
  .unwrap()
  |> ignore
  let run_custody = connected.database
    .read("client_run_custody", "issued")
    .unwrap()
  let submission_custody = connected.database
    .read("client_submitted_intent_custody", "issued")
    .unwrap()
  let path = connected.session.state_path
  let parent_path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  connected.close().unwrap()
  assert_true(connected.configuration() is Err(Closed))
  let restored = begin_native_local_host_adoption(
      parent_path,
      "local-final-reopen.host",
      parent_path,
      "local-final-reopen.account.json",
      "operator",
      epoch_test_crypto(),
    )
    .unwrap()
    .open_journal(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    )
    .unwrap()
  assert_eq(restored.session.state_path, path)
  assert_eq(restored.adoption_cid(), adoption)
  assert_eq(
    restored.database.read("client_submission_epoch", "authority").unwrap().body,
    epoch_body.body,
  )
  assert_eq(
    restored.database.read("client_run_custody", "issued").unwrap().body,
    run_custody.body,
  )
  assert_eq(
    restored.database.read("client_submitted_intent_custody", "issued").unwrap().body,
    submission_custody.body,
  )
  assert_eq(
    restored
    .epoch_authority()
    .unwrap()
    .verify_epoch(epoch, "sha256:" + "a".repeat(64), true, 1001.0)
    .unwrap(),
    @scope.Admissible,
  )
  guard restored.run_journal().unwrap().lookup(request, true)
    is Ok(Retained(record)) else {
    fail("original Run lost")
  }
  assert_eq(
    @publication.run_definition_run_id(record.definition).unwrap(),
    "original-run",
  )
  assert_eq(restored.configuration().unwrap().entry_count(), 0)
  restored.close().unwrap()
  restored.close().unwrap()
}

///|
test "Native Local atomic adoption refuses preexisting custody before generating an epoch" {
  for
    index, record_namespace in [
      "client_runs", "client_cancel_originals", "client_submitted_intents", "client_effect_response_bytes",
      "client_local_adoption", "client_local_read_custody", "client_local_read_evidence",
      "client_local_grant_custody", "client_local_grant_originals",
    ] {
    let database = epoch_test_database(
      "local-final-foreign-" + index.to_string(),
    )
    database.insert(record_namespace, "foreign", b"original").unwrap() |> ignore
    assert_true(
      initialize_native_local_client_custody(
        database,
        epoch_test_crypto(),
        b"adoption",
      )
      is Err(CustodyLost),
    )
    assert_true(
      database.read("client_submission_epoch", "authority")
      is Err(@sqlite.NotFound),
    )
    assert_eq(
      database.read(record_namespace, "foreign").unwrap().body,
      b"original",
    )
    database.close_checked().unwrap()
  }
}

///|
test "Native Local commit response loss preserves all original custody in one transaction" {
  for reply_lost in [false, true] {
    let name = "local-final-commit-" + reply_lost.to_string()
    let database = epoch_test_database(name)
    if reply_lost {
      client_test_fail_commit_reply(database, 1)
    } else {
      client_test_fail_commit(database, 1)
    }
    assert_true(
      initialize_native_local_client_custody(
        database,
        epoch_test_crypto(),
        b"exact-adoption",
      )
      is Err(TransactionUnknown),
    )
    assert_true(database.transaction_fenced())
    assert_true(
      initialize_native_local_client_custody(
        database,
        epoch_test_crypto(),
        b"replacement",
      )
      is Err(Fenced),
    )
    if !reply_lost {
      database.rollback().unwrap()
    }
    database.close_checked().unwrap()
    let restored = local_journal_test_library()
      .open_existing_database(
        @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
        "/" +
        name +
        ".sqlite3",
        65536L,
      )
      .unwrap()
    for
      (record_namespace, key) in [
        ("client_local_adoption", "adoption"),
        ("client_submission_epoch", "authority"),
        ("client_run_custody", "issued"),
        ("client_cancel_custody", "issued"),
        ("client_submitted_intent_custody", "issued"),
      ] {
      if reply_lost {
        assert_true(restored.read(record_namespace, key) is Ok(_))
      } else {
        assert_true(
          restored.read(record_namespace, key) is Err(@sqlite.NotFound),
        )
      }
    }
    if reply_lost {
      assert_eq(
        restored.read("client_local_adoption", "adoption").unwrap().body,
        b"exact-adoption",
      )
      assert_true(
        initialize_native_local_client_custody(
          restored,
          epoch_test_crypto(),
          b"replacement",
        )
        is Err(CustodyLost),
      )
    }
    restored.close_checked().unwrap()
  }
}

///|
test "Native Local retained journal never recreates a lost final adoption" {
  let connected = local_journal_test_connection("local-final-lost")
  let original_epoch = connected.database
    .read("client_submission_epoch", "authority")
    .unwrap()
  let record_namespace = @utf8.encode("client_local_adoption")
  let record_key = @utf8.encode("adoption")
  assert_true(
    submitted_test_remove_record(
      connected.database,
      record_namespace,
      record_namespace.length(),
      record_key,
      record_key.length(),
    ),
  )
  assert_true(connected.check_binding() is Err(CustodyLost))
  connected.close().unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let session = begin_native_local_host_adoption(
    path,
    "local-final-lost.host",
    path,
    "local-final-lost.account.json",
    "operator",
    epoch_test_crypto(),
  ).unwrap()
  guard session.open_journal(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    )
    is Err(DatabasePending(database, CustodyLost)) else {
    fail("missing final adoption was repaired")
  }
  assert_eq(
    database.read("client_submission_epoch", "authority").unwrap().body,
    original_epoch.body,
  )
  assert_true(
    database.read("client_local_adoption", "adoption") is Err(@sqlite.NotFound),
  )
  database.close_checked().unwrap()
  assert_true(session.close())
}

///|
test "Native Local configuration loss after journal adoption never restores removed grants" {
  let connected = local_journal_test_connection("local-final-config-lost")
  let root = connected.session.root
  for name in ["account.json", "configuration-custody.json"] {
    root
    .reclaim_generation(name, root.inspect_generation(name).unwrap().unwrap())
    .unwrap()
  }
  assert_true(connected.configuration() is Err(CustodyLost))
  assert_eq(root.inspect_generation("account.json").unwrap(), None)
  assert_eq(
    root.inspect_generation("configuration-custody.json").unwrap(),
    None,
  )
  connected.close().unwrap()
}

///|
#borrow(database)
extern "C" fn local_test_fail_close(
  database : @sqlite.Database,
  failures : Int,
) -> Unit = "actql_native_sqlite_test_fail_close"

///|
test "Native Local close failure fences access and retains the same lock until cleanup succeeds" {
  let connected = local_journal_test_connection("local-final-close")
  local_test_fail_close(connected.database, 1)
  assert_true(connected.close() is Err(Physical(_)))
  assert_true(connected.configuration() is Err(Closed))
  assert_false(connected.database_closed)
  assert_false(connected.session_closed)
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  assert_true(
    begin_native_local_host_adoption(
      path,
      "local-final-close.host",
      path,
      "local-final-close.account.json",
      "operator",
      epoch_test_crypto(),
    )
    is Err(Filesystem(@filesystem.Lock(_))),
  )
  connected.close().unwrap()
  assert_true(connected.database_closed)
  assert_true(connected.session_closed)
  connected.close().unwrap()
}

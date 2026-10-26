///|
fn journal_open_original(name : String) -> NativeLocalAdoptionSession {
  let seeded = local_journal_test_connection(name)
  seeded.close_owned_root_descriptors().unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  begin_existing_native_local_host_adoption_with_custody(
    path,
    name + ".host",
    path,
    name + ".account.json",
    "operator",
    epoch_test_crypto(),
  ).unwrap()
}

///|
fn journal_open_refusal(
  result : Result[NativeLocalHostConnection, NativeLocalJournalOpenFailure],
) -> NativeLocalJournalOpenFailure raise {
  match result {
    Err(original) => original
    Ok(_) => {
      fail("journal acquisition unexpectedly succeeded")
      abort("unreachable")
    }
  }
}

///|
test "custodied existing journal opens the original epoch and adoption without initialization" {
  let session = journal_open_original("journal-custody-existing")
  let intent = session.intent_cid()
  let host = session
    .open_existing_journal_with_custody(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    )
    .unwrap()
  let epoch = host.database
    .read("client_submission_epoch", "authority")
    .unwrap()
  let adoption = host.adoption_cid()
  assert_true(physical_equal(host.session, session))
  assert_true(session.existing_only)
  assert_false(session.initial_signing_eligible.val)
  assert_true(session.journal_open_failure is None)
  host.close_owned_root_descriptors().unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let restored = begin_existing_native_local_host_adoption_with_custody(
      path,
      "journal-custody-existing.host",
      path,
      "journal-custody-existing.account.json",
      "operator",
      epoch_test_crypto(),
    )
    .unwrap()
    .open_existing_journal_with_custody(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    )
    .unwrap()
  assert_eq(restored.session.intent_cid(), intent)
  assert_eq(restored.adoption_cid(), adoption)
  assert_eq(
    restored.database.read("client_submission_epoch", "authority").unwrap().body,
    epoch.body,
  )
  restored.close_owned_root_descriptors().unwrap()
}

///|
test "custodied existing journal refuses a first initialization Session without creating a database" {
  let session = local_settings_fixture("journal-custody-first")
  assert_false(session.existing_only)
  let failed = journal_open_refusal(
    session.open_existing_journal_with_custody(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    ),
  )
  assert_true(failed.issue() is InvalidInput)
  assert_true(failed.database is None)
  assert_true(
    session.root.inspect_generation("client.sqlite3").unwrap() is None,
  )
  adoption_open_require_locked(session.parent)
  assert_true(session.close())
  failed.retry_cleanup().unwrap()
  assert_true(session.root.private_ownership() is Err(_))
  assert_true(failed.issue() is InvalidInput)
}

///|
test "custodied invalid journal limits retain distinct Roots and preserve a borrowed original" {
  let session = journal_open_original("journal-custody-limit")
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let borrowed = @filesystem.open_private_root(path).unwrap()
  assert_false(physical_equal(session.parent, session.source_root))
  let failed = journal_open_refusal(
    session.open_existing_journal_with_custody(
      local_journal_test_library(),
      epoch_test_crypto(),
      0.0,
      8,
      8388608L,
    ),
  )
  assert_true(failed.issue() is InvalidInput)
  assert_true(failed.database is None)
  assert_true(session.check_original() is Err(Closed))
  adoption_open_require_locked(borrowed)
  failed.retry_cleanup().unwrap()
  assert_true(session.parent.private_ownership() is Err(_))
  assert_true(session.source_root.private_ownership() is Err(_))
  assert_true(session.root.private_ownership() is Err(_))
  borrowed.private_ownership().unwrap() |> ignore
  let next = borrowed.acquire_lock_with_custody("local-adoption.lock").unwrap()
  next.close_checked().unwrap()
  borrowed.close().unwrap()
  assert_true(session.close())
}

///|
test "custodied missing original database is never repaired or issued a replacement epoch" {
  let session = journal_open_original("journal-custody-no-db")
  let root = session.root
  let original = root.inspect_generation("client.sqlite3").unwrap().unwrap()
  root.reclaim_generation("client.sqlite3", original).unwrap()
  let failed = journal_open_refusal(
    session.open_existing_journal_with_custody(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    ),
  )
  assert_true(failed.issue() is CustodyLost)
  assert_true(failed.database is None)
  assert_true(root.inspect_generation("client.sqlite3").unwrap() is None)
  adoption_open_require_locked(session.parent)
  failed.retry_cleanup().unwrap()
  assert_true(failed.issue() is CustodyLost)
}

///|
fn journal_open_lost_adoption(
  name : String,
) -> NativeLocalAdoptionSession raise {
  let host = local_journal_test_connection(name)
  let run_namespace = @utf8.encode("client_local_adoption")
  let key = @utf8.encode("adoption")
  assert_true(
    submitted_test_remove_record(
      host.database,
      run_namespace,
      run_namespace.length(),
      key,
      key.length(),
    ),
  )
  host.close_owned_root_descriptors().unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  begin_existing_native_local_host_adoption_with_custody(
    path,
    name + ".host",
    path,
    name + ".account.json",
    "operator",
    epoch_test_crypto(),
  ).unwrap()
}

///|
test "custodied database close failure keeps the same primary database Roots and lock through Session aliases" {
  let session = journal_open_lost_adoption("journal-custody-db-close")
  let failed = journal_open_refusal(
    session.open_existing_journal_with_custody(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    ),
  )
  guard failed.issue() is DatabasePending(database, CustodyLost) else {
    fail("original pending database was lost")
  }
  assert_true(physical_equal(failed.database.unwrap(), database))
  let epoch = database.read("client_submission_epoch", "authority").unwrap()
  local_test_fail_close(database, 1)
  assert_false(session.close())
  assert_true(physical_equal(failed.database.unwrap(), database))
  assert_true(session.root.private_ownership() is Ok(_))
  assert_true(session.parent.private_ownership() is Ok(_))
  assert_true(session.source_root.private_ownership() is Ok(_))
  adoption_open_require_locked(session.parent)
  assert_eq(
    database.read("client_submission_epoch", "authority").unwrap().body,
    epoch.body,
  )
  assert_true(
    database.read("client_local_adoption", "adoption") is Err(@sqlite.NotFound),
  )
  failed.retry_cleanup().unwrap()
  assert_true(failed.database is None)
  assert_true(
    failed.issue() is DatabasePending(retained, CustodyLost) &&
    physical_equal(retained, database),
  )
  let closes = local_owned_roots_checked_close_count(database)
  assert_true(session.close())
  failed.retry_cleanup().unwrap()
  assert_eq(local_owned_roots_checked_close_count(database), closes)
}

///|
test "custodied repeated journal open returns the same refusal without reopening or rebinding originals" {
  let session = journal_open_lost_adoption("journal-custody-repeat")
  let failed = journal_open_refusal(
    session.open_existing_journal_with_custody(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    ),
  )
  let repeated = journal_open_refusal(
    session.open_existing_journal_with_custody(
      local_journal_test_library(),
      epoch_test_crypto(),
      200.0,
      16,
      16777216L,
    ),
  )
  assert_true(physical_equal(failed, repeated))
  assert_true(
    failed.issue() is DatabasePending(original, CustodyLost) &&
    physical_equal(original, failed.database.unwrap()),
  )
  failed.retry_cleanup().unwrap()
  let after_close = journal_open_refusal(
    session.open_existing_journal_with_custody(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    ),
  )
  assert_true(physical_equal(failed, after_close))
  assert_true(after_close.issue() is DatabasePending(_, CustodyLost))
}

///|
// Deliberately unconfirmed fixture originals remain retained through process
// exit. Test-owned lock retirement below is not the Reader/Root cleanup ACK.
let journal_open_pending_originals : Array[NativeLocalJournalOpenFailure] = []

///|
test "custodied original Reader Unknown prevents database open and keeps the actual exclusive lock" {
  let session = journal_open_original("journal-custody-reader")
  let reader = session.source_root
    .open_reader(session.source_name, session.source_generation)
    .unwrap()
  assert_true(adoption_reader_consumed_unknown(reader))
  session.retain_read_issue(
    ReadPending(reader, @filesystem.Cleanup("original reader unconfirmed")),
  )
  |> ignore
  let failed = journal_open_refusal(
    session.open_existing_journal_with_custody(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    ),
  )
  assert_true(failed.database is None)
  for _ in 0..<2 {
    assert_true(
      failed.retry_cleanup() is Err(Filesystem(@filesystem.Read(message))) &&
      message == "reader retirement observation unavailable",
    )
    assert_false(session.close())
    assert_true(
      failed.issue() is ReadPending(original, _) &&
      physical_equal(original, reader),
    )
    adoption_open_require_locked(session.parent)
    assert_true(session.root.private_ownership() is Ok(_))
  }
  session.lock.close_checked().unwrap()
  session.root.close().unwrap()
  session.source_root.close().unwrap()
  session.parent.close().unwrap()
  journal_open_pending_originals.push(failed)
}

///|
test "custodied Root Unknown never falls through to release the journal acquisition lock" {
  let session = journal_open_original("journal-custody-root")
  let failed = journal_open_refusal(
    session.open_existing_journal_with_custody(
      local_journal_test_library(),
      epoch_test_crypto(),
      0.0,
      8,
      8388608L,
    ),
  )
  let source = session.source_root
  adoption_open_fail_census_close(source, 1)
  assert_true(source.check_directory_members([]) is Err(@filesystem.Cleanup(_)))
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let borrowed = @filesystem.open_private_root(path).unwrap()
  for _ in 0..<2 {
    assert_true(
      failed.retry_cleanup() is Err(Filesystem(@filesystem.Cleanup(_))),
    )
    assert_false(session.close())
    assert_true(failed.issue() is InvalidInput)
    assert_true(
      failed.acquisition.source_root is Some(original) &&
      physical_equal(original, source),
    )
    adoption_open_require_locked(borrowed)
  }
  session.lock.close_checked().unwrap()
  borrowed.close().unwrap()
  journal_open_pending_originals.push(failed)
}

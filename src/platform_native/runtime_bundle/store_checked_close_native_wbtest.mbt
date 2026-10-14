///|
#borrow(database)
extern "C" fn bundle_close_fail_database(
  database : @sqlite.Database,
  failures : Int,
) -> Unit = "actql_native_sqlite_test_fail_close"

///|
#borrow(database)
extern "C" fn bundle_close_database_attempts(
  database : @sqlite.Database,
) -> Int = "actql_native_sqlite_test_checked_close_count"

///|
#borrow(lock)
extern "C" fn bundle_close_lose_lock_observation(
  lock : @filesystem.Lock,
) -> Bool = "actql_native_filesystem_test_lock_consumed_unknown"

///|
test "Bundle Store checked retirement preserves durable holdings and retries the same database" {
  // This existing physical fixture fails when any library/root input is absent.
  // It is not an environment-gated return counted as a successful Native test.
  let (store, sqlite, crypto, path) = native_retention_fixture(
    "checked-close-database",
  )
  let held = store
    .retain(native_bundle_cid("1"), "original-process", "process")
    .unwrap()
  assert_eq(held.state[2], "1")
  store.database
  .insert("close-fixture", "original-result", b"independent durable result")
  .unwrap()
  |> ignore
  assert_true(
    store.database
    .reserve_capacity("close-fixture", "original-hold", 7L, 1L, 128L, 4L)
    .unwrap(),
  )
  bundle_close_fail_database(store.database, 1)
  assert_true(store.close_checked() is Err(Database(@sqlite.Physical(_))))
  assert_false(store.closed)
  assert_true(store.retiring)
  assert_true(store.active() is Err(CleanupPending))
  assert_true(store.capacity_usage() is Err(CleanupPending))
  assert_true(store.release("original-process") is Err(CleanupPending))
  assert_eq(bundle_close_database_attempts(store.database), 1)
  assert_eq(
    store.database.capacity_usage("close-fixture").unwrap().reserved_bytes,
    7L,
  )
  assert_true(
    store.root.inspect_generation(".actql-runtime-bundle.sqlite3").unwrap()
    is Some(_),
  )
  store.close_checked().unwrap()
  assert_true(store.closed)
  assert_eq(bundle_close_database_attempts(store.database), 2)
  store.close_checked().unwrap()
  assert_false(store.close().unwrap())
  assert_eq(bundle_close_database_attempts(store.database), 2)
  assert_true(
    store.root.inspect_generation(".actql-runtime-bundle.sqlite3") is Err(_),
  )
  // Handle retirement is not a bundle release or an independent reservation ACK.
  let restored = open_runtime_bundle_store(
    sqlite,
    crypto,
    path,
    native_bundle_authorities(),
    "aarch64-apple-darwin",
    22L,
    8,
    8,
    1048576L,
  ).unwrap()
  assert_eq(
    restored.inspect(native_bundle_cid("1")).unwrap().unwrap().state[2],
    "1",
  )
  assert_eq(
    restored.database.read("close-fixture", "original-result").unwrap().body,
    b"independent durable result",
  )
  assert_eq(
    restored.database.capacity_usage("close-fixture").unwrap().reserved_bytes,
    7L,
  )
  assert_true(restored.release("original-process").unwrap())
  restored.close_checked().unwrap()
}

///|
test "Bundle Store Lock close Unknown keeps the outer Root and blocks further catalog I/O" {
  let (store, _, _, _) = native_retention_fixture("checked-close-lock-unknown")
  // A real descriptor close followed by lost observation, not an observed
  // kernel EINTR/EIO fault. Retrying must not close a reused descriptor.
  assert_true(bundle_close_lose_lock_observation(store.lock))
  assert_true(store.close_checked() is Err(Filesystem(@filesystem.Cleanup(_))))
  assert_false(store.closed)
  assert_true(store.retiring)
  assert_eq(bundle_close_database_attempts(store.database), 1)
  assert_true(store.list() is Err(CleanupPending))
  assert_true(store.recover() is Err(CleanupPending))
  let writer = store.root.create_writer("independent-reused-fd", 3L).unwrap()
  assert_true(store.close_checked() is Err(Filesystem(@filesystem.Cleanup(_))))
  assert_eq(bundle_close_database_attempts(store.database), 1)
  writer.append(b"abc").unwrap()
  writer.cancel().unwrap()
  assert_true(
    store.root.inspect_generation(".actql-runtime-bundle.sqlite3").unwrap()
    is Some(_),
  )
  assert_false(store.closed)
}

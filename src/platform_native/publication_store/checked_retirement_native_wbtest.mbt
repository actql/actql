///|
#borrow(lock)
extern "C" fn store_close_lock_observation_loss(lock : @filesystem.Lock) -> Bool = "actql_native_filesystem_test_lock_consumed_unknown"

///|
test "Store close retains original owners and durable reservation through database cleanup retry" {
  let (library, path) = store_open_custody_fixture("store-close-retry")
  let authority = native_payload_cid("store-close-retry-authority")
  let store = open_store_with_custody(
    library, path, authority, 128L, 4L, 4096L, diagnostic_ceiling=Some(256),
  ).unwrap()
  store.database.insert("fixture-original", "result", b"independent original").unwrap() |> ignore
  assert_true(store.database.reserve_capacity("fixture-original", "hold", 7L, 1L, 128L, 4L).unwrap())
  store_open_fail_close(store.database, 1)
  assert_true(store.close() is Err(Database(@sqlite.Physical(_))))
  assert_false(store.closed)
  assert_true(store.retiring)
  assert_true(store.capacity_usage() is Err(CleanupPending))
  assert_true(store.recover() is Err(CleanupPending))
  assert_true(store.root.inspect_generation(".actql-publication.sqlite3").unwrap() is Some(_))
  assert_eq(store.database.capacity_usage("fixture-original").unwrap().reserved_bytes, 7L)
  assert_true(store.close().unwrap())
  assert_true(store.closed)
  assert_false(store.close().unwrap())
  // Store handle retirement does not reclaim separately retained data/holding.
  let restored = open_existing_store_with_custody(
    library, path, authority, 128L, 4L, 4096L, diagnostic_ceiling=Some(256),
  ).unwrap()
  assert_eq(restored.database.read("fixture-original", "result").unwrap().body, b"independent original")
  assert_eq(restored.database.capacity_usage("fixture-original").unwrap().reserved_bytes, 7L)
  assert_eq(restored.database.capacity_usage("fixture-original").unwrap().reserved_objects, 1L)
  assert_true(restored.close().unwrap())
}

///|
test "Store Lock close Unknown holds the outer Root and never returns an overall close acknowledgement" {
  let (library, path) = store_open_custody_fixture("store-close-lock-unknown")
  let store = open_store_with_custody(
    library, path, native_payload_cid("store-close-lock-authority"), 128L, 4L, 4096L,
    diagnostic_ceiling=Some(256),
  ).unwrap()
  // A real close followed by missing observation, not an actual kernel fault.
  assert_true(store_close_lock_observation_loss(store.lock))
  assert_true(store.close() is Err(Filesystem(@filesystem.Cleanup(_))))
  assert_false(store.closed)
  assert_true(store.retiring)
  assert_true(store.capacity_usage() is Err(CleanupPending))
  // Subsequent retries use the same idempotent DB and sticky consumed Lock.
  // They neither run recover on the closed DB nor touch a reused descriptor.
  assert_true(store.close() is Err(Filesystem(@filesystem.Cleanup(_))))
  assert_true(store.root.inspect_generation(".actql-publication.sqlite3").unwrap() is Some(_))
  assert_false(store.closed)
}

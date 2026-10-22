///|
#borrow(lock)
extern "C" fn store_close_lock_observation_loss(
  lock : @filesystem.Lock,
) -> Bool = "actql_native_filesystem_test_lock_consumed_unknown"

///|
test "Store close retains original owners and durable reservation through database cleanup retry" {
  let (library, path) = store_open_custody_fixture("store-close-retry")
  let authority = native_payload_cid("store-close-retry-authority")
  let store = open_store_with_custody(
    library,
    path,
    authority,
    128L,
    4L,
    4096L,
    diagnostic_ceiling=Some(256),
  ).unwrap()
  store.retained_data_current().unwrap()
  let request = native_payload_request(
    authority, "store-close-retry-payload", 16L,
  )
  let writer = store.begin_payload(request).unwrap()
  assert_true(store.close() is Err(CleanupPending))
  assert_false(store.retiring)
  writer.append(b"held").unwrap()
  let info = writer.seal().unwrap()
  let reader = store.open_payload_reader(info.material_generation_cid).unwrap()
  // A live original child is not a retirement ACK and does not itself
  // invalidate immutable DATA within the caller's admitted operation.
  store.retained_data_current().unwrap()
  assert_true(store.close() is Err(CleanupPending))
  assert_false(store.retiring)
  assert_eq(reader.next(4).unwrap().bytes, b"held")
  reader.finish().unwrap()
  // Existing opaque cleanup shape in a whitebox counter, not a new public
  // cleanup admission. A refusing retry must retain this same responsibility.
  let cleanup : PayloadCleanupOwner = { store, request, complete: false, }
  store.database
  .insert("fixture-original", "result", b"independent original")
  .unwrap()
  |> ignore
  assert_true(
    store.database
    .reserve_capacity("fixture-original", "hold", 7L, 1L, 128L, 4L)
    .unwrap(),
  )
  store_open_fail_close(store.database, 1)
  assert_true(store.close() is Err(Database(@sqlite.Physical(_))))
  assert_false(store.closed)
  assert_true(store.retiring)
  assert_true(store.retained_data_current() is Err(CleanupPending))
  assert_true(store.capacity_usage() is Err(CleanupPending))
  assert_true(store.recover() is Err(CleanupPending))
  assert_true(cleanup.retry() is Err(CleanupPending))
  assert_false(cleanup.complete)
  let calls = Ref(0)
  assert_true(
    allocation_prepare(store, "retiring-counter", fn() {
      calls.val += 1
      Ok(())
    })
    is Err(CleanupPending),
  )
  assert_eq(calls.val, 0)
  assert_true(
    store.root.inspect_generation(".actql-publication.sqlite3").unwrap()
    is Some(_),
  )
  assert_eq(
    store.database.capacity_usage("fixture-original").unwrap().reserved_bytes,
    7L,
  )
  assert_true(store.close().unwrap())
  assert_true(store.closed)
  assert_true(store.retained_data_current() is Err(Closed))
  assert_false(store.close().unwrap())
  // Store handle retirement does not reclaim separately retained data/holding.
  let restored = match
    open_existing_store_with_custody(
      library,
      path,
      authority,
      128L,
      4L,
      4096L,
      diagnostic_ceiling=Some(256),
    ) {
    Ok(value) => value
    Err(RefusedBeforeAcquisition(_)) =>
      fail("restoring the retained original refused before acquisition")
    Err(CleanupRequired(failure)) =>
      match failure.issue() {
        Database(@sqlite.DatabaseOpen(detail)) => fail(detail)
        Filesystem(@filesystem.RootOpen(detail)) => fail(detail)
        Filesystem(@filesystem.Lock(detail)) => fail(detail)
        LegacyStoreFormat(detail) => fail("legacy original: " + detail)
        UnknownStoreFormat(detail) => fail("unidentified original: " + detail)
        StoreFormatIo(detail) => fail("original format I/O: " + detail)
        _ => fail("restoring the retained original holds acquired cleanup")
      }
  }
  assert_eq(
    restored.database.read("fixture-original", "result").unwrap().body,
    b"independent original",
  )
  assert_eq(
    restored.database.capacity_usage("fixture-original").unwrap().reserved_bytes,
    7L,
  )
  assert_eq(
    restored.database.capacity_usage("fixture-original").unwrap().reserved_objects,
    1L,
  )
  assert_true(restored.close().unwrap())
  let (callback_library, callback_path) = store_open_custody_fixture(
    "store-close-callback",
  )
  let callback_store = open_store_with_custody(
    callback_library,
    callback_path,
    native_payload_cid("store-close-callback-authority"),
    128L,
    4L,
    4096L,
    diagnostic_ceiling=Some(256),
  ).unwrap()
  let close_result : Ref[Result[Bool, NativePublicationStoreIssue]?] = Ref(None)
  callback_store.allocation_failure.val = Some(fn(_) {
    close_result.val = Some(callback_store.close())
    None
  })
  assert_true(
    allocation_prepare(callback_store, "close-before-operation", fn() {
      calls.val += 1
      Ok(())
    })
    is Err(Closed),
  )
  assert_true(close_result.val is Some(Ok(true)))
  assert_eq(calls.val, 0)
}

///|
test "Store Lock close Unknown holds the outer Root and never returns an overall close acknowledgement" {
  let (library, path) = store_open_custody_fixture("store-close-lock-unknown")
  let store = open_store_with_custody(
    library,
    path,
    native_payload_cid("store-close-lock-authority"),
    128L,
    4L,
    4096L,
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
  assert_true(
    store.root.inspect_generation(".actql-publication.sqlite3").unwrap()
    is Some(_),
  )
  assert_false(store.closed)
}

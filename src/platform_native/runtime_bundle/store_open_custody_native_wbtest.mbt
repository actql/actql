///|
fn bundle_open_custody_fixture(
  name : String,
) -> (@sqlite.Library, @signature.Library, String) {
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT").unwrap()
  let root = @filesystem.open_root(parent).unwrap()
  root.create_directory(name).unwrap() |> ignore
  root.close().unwrap()
  (
    @sqlite.load_library(
      @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
    ).unwrap(),
    @signature.load_library(
      @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
    ).unwrap(),
    parent + "/" + name,
  )
}

///|
test "Bundle constructor refusal and original failed SQLite custody remain distinct" {
  let (sqlite, crypto, path) = bundle_open_custody_fixture(
    "bundle-open-failed-db",
  )
  assert_true(
    open_runtime_bundle_store_with_custody(
      sqlite,
      crypto,
      path,
      [],
      "aarch64-apple-darwin",
      22L,
      8,
      8,
      1048576L,
    )
    is Err(RefusedBeforeAcquisition(InvalidConfiguration)),
  )
  let root = @filesystem.open_root(path).unwrap()
  assert_eq(
    root.inspect_generation(".actql-runtime-bundle.lock").unwrap(),
    None,
  )
  root.create_directory(".actql-runtime-bundle.sqlite3").unwrap() |> ignore
  root.close().unwrap()
  let failure = match
    open_runtime_bundle_store_with_custody(
      sqlite,
      crypto,
      path,
      native_bundle_authorities(),
      "aarch64-apple-darwin",
      22L,
      8,
      8,
      1048576L,
    ) {
    Err(CleanupRequired(original)) => original
    _ => {
      fail("failed SQLite construction discarded its acquired custody")
      return
    }
  }
  assert_true(failure.issue() is Database(@sqlite.DatabaseOpen(_)))
  assert_true(failure.failed_database is Some(_))
  assert_true(failure.lock is Some(_))
  assert_true(failure.root is Some(_))
  failure.retry_cleanup().unwrap()
  assert_true(failure.failed_database is None)
  assert_true(failure.lock is None)
  assert_true(failure.root is None)
  failure.retry_cleanup().unwrap()
  assert_true(failure.issue() is Database(@sqlite.DatabaseOpen(_)))
}

///|
test "Bundle catalog rejection retains the same initialized DB until checked cleanup" {
  let (sqlite, crypto, path) = bundle_open_custody_fixture(
    "bundle-open-bad-catalog",
  )
  let original = open_runtime_bundle_store_with_custody(
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
  original.database.insert("independent", "original", b"untouched").unwrap()
  |> ignore
  let catalog = original.database.read("runtime_bundle", "catalog").unwrap()
  original.database
  .compare_exchange("runtime_bundle", "catalog", catalog.revision, b"invalid")
  .unwrap()
  |> ignore
  // Fault setup retires real handles without asking the invalid catalog to
  // prove a successful Store transition. The production reopen rejects it.
  original.database.close_checked().unwrap()
  original.lock.close_checked().unwrap()
  original.root.close().unwrap()
  let failure = match
    open_runtime_bundle_store_with_custody(
      sqlite,
      crypto,
      path,
      native_bundle_authorities(),
      "aarch64-apple-darwin",
      22L,
      8,
      8,
      1048576L,
    ) {
    Err(CleanupRequired(same)) => same
    _ => {
      fail("invalid catalog lost initialized handles or was repaired")
      return
    }
  }
  let database = failure.database.unwrap()
  let lock = failure.lock.unwrap()
  let root = failure.root.unwrap()
  bundle_close_fail_database(database, 1)
  assert_true(failure.retry_cleanup() is Err(Database(@sqlite.Physical(_))))
  assert_true(physical_equal(database, failure.database.unwrap()))
  assert_true(physical_equal(lock, failure.lock.unwrap()))
  assert_true(physical_equal(root, failure.root.unwrap()))
  assert_eq(bundle_close_database_attempts(database), 1)
  failure.retry_cleanup().unwrap()
  assert_eq(bundle_close_database_attempts(database), 2)
  failure.retry_cleanup().unwrap()
  assert_eq(bundle_close_database_attempts(database), 2)
  let restored = sqlite
    .open_existing_database(path + "/.actql-runtime-bundle.sqlite3", 1048576L)
    .unwrap()
  assert_eq(
    restored.read("runtime_bundle", "catalog").unwrap().body,
    b"invalid",
  )
  assert_eq(
    restored.read("independent", "original").unwrap().body,
    b"untouched",
  )
  restored.close_checked().unwrap()
}

///|
test "Bundle failed preparation Lock Unknown preserves outer Root and never recloses its FD" {
  let (store, _, _, _) = native_retention_fixture("bundle-open-lock-unknown")
  let failure = bundle_store_open_failure(
    StateCollision,
    root=Some(store.root),
    lock=Some(store.lock),
    database=Some(store.database),
  )
  assert_true(bundle_close_lose_lock_observation(store.lock))
  assert_true(
    failure.retry_cleanup() is Err(Filesystem(@filesystem.Cleanup(_))),
  )
  assert_true(failure.database is None)
  assert_true(failure.lock is Some(same) && physical_equal(same, store.lock))
  assert_true(failure.root is Some(same) && physical_equal(same, store.root))
  let writer = store.root.create_writer("independent-fd-reuse", 3L).unwrap()
  assert_true(
    failure.retry_cleanup() is Err(Filesystem(@filesystem.Cleanup(_))),
  )
  writer.append(b"abc").unwrap()
  writer.cancel().unwrap()
  assert_true(failure.issue() is StateCollision)
}

///|
test "Bundle verification Reader stays with original Store until its checked retirement" {
  let (store, _, _, _) = native_retention_fixture(
    "bundle-verification-reader-pending",
  )
  let generation = store.root.inspect_generation("artifact").unwrap().unwrap()
  let reader = store.root
    .open_reader_with_custody("artifact", generation)
    .unwrap()
  store.component_reader = Some(reader)
  assert_true(store.active() is Err(CleanupPending))
  assert_true(
    store.component_reader is Some(same) && physical_equal(same, reader),
  )
  assert_eq(bundle_close_database_attempts(store.database), 0)
  assert_true(
    store.acquire_active_component_with_custody("foreign", "foreign", "process")
    is Err(RefusedBeforeHolding(CleanupPending)),
  )
  store.close_checked().unwrap()
  assert_true(store.component_reader is None)
  assert_true(store.closed)
  assert_eq(bundle_close_database_attempts(store.database), 1)
  store.close_checked().unwrap()
  assert_eq(bundle_close_database_attempts(store.database), 1)
}

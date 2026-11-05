///|
/// Required isolated fixture, not an environment-missing success. Tests below
/// distinguish real constructor calls from an injected post-open refusal.
fn store_open_custody_fixture(name : String) -> (@sqlite.Library, String) {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_root(path, diagnostic_ceiling=Some(256)).unwrap()
  parent.create_directory(name).unwrap() |> ignore
  parent.close().unwrap()
  (
    @sqlite.load_library(
      @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
      diagnostic_ceiling=Some(256),
    ).unwrap(),
    path + "/" + name,
  )
}

///|
#borrow(database)
extern "C" fn store_open_fail_close(
  database : @sqlite.Database,
  failures : Int,
) -> Unit = "actql_native_sqlite_test_fail_close"

///|
#borrow(database)
extern "C" fn store_open_drop_capacity(database : @sqlite.Database) -> Bool = "actql_native_sqlite_test_drop_capacity"

///|
test "Store preparation cleanup keeps original Root and lock while database close is pending" {
  let (library, path) = store_open_custody_fixture("store-open-pending")
  let original = open_store_with_custody(
    library,
    path,
    native_payload_cid("store-open-pending-authority"),
    128L,
    4L,
    4096L,
    diagnostic_ceiling=Some(256),
  ).unwrap()
  original.database.insert("original", "input", b"unchanged").unwrap() |> ignore
  store_open_fail_close(original.database, 1)
  // Inject an unavailable identity observation after a genuine preparation.
  // The production factory and cleanup methods own these same real handles.
  let failure = store_open_failure(
    StateCollision,
    root=Some(original.root),
    lock=Some(original.lock),
    database=Some(original.database),
  )
  assert_true(failure.retry_cleanup() is Err(Database(@sqlite.Physical(_))))
  assert_true(physical_equal(failure.database.unwrap(), original.database))
  assert_true(physical_equal(failure.lock.unwrap(), original.lock))
  assert_true(physical_equal(failure.root.unwrap(), original.root))
  assert_true(failure.issue() is StateCollision)
  failure.retry_cleanup().unwrap()
  assert_true(failure.database is None)
  assert_true(failure.lock is None)
  assert_true(failure.root is None)
  failure.retry_cleanup().unwrap()
  assert_true(failure.issue() is StateCollision)
  let restored = open_existing_store_with_custody(
    library,
    path,
    native_payload_cid("store-open-pending-authority"),
    128L,
    4L,
    4096L,
    diagnostic_ceiling=Some(256),
  ).unwrap()
  assert_eq(
    restored.database.read("original", "input").unwrap().body,
    b"unchanged",
  )
  restored.database.close_checked().unwrap()
  assert_true(restored.lock.close())
  restored.root.close().unwrap()
}

///|
test "existing Store failed-open custody refuses missing schema without repair" {
  let (library, path) = store_open_custody_fixture("store-open-schema")
  let authority = native_payload_cid("store-open-schema-authority")
  let original = open_store_with_custody(
    library,
    path,
    authority,
    128L,
    4L,
    4096L,
    diagnostic_ceiling=Some(256),
  ).unwrap()
  original.database.insert("original", "input", b"original").unwrap() |> ignore
  assert_true(store_open_drop_capacity(original.database))
  original.database.close_checked().unwrap()
  assert_true(original.lock.close())
  original.root.close().unwrap()
  let failure = match
    open_existing_store_with_custody(
      library,
      path,
      authority,
      128L,
      4L,
      4096L,
      diagnostic_ceiling=Some(256),
    ) {
    Err(CleanupRequired(value)) => value
    Err(RefusedBeforeAcquisition(_)) => {
      fail("acquired Store failure lost its original cleanup custody")
      return
    }
    Ok(_) => {
      fail("lost original schema was initialized or repaired")
      return
    }
  }
  assert_true(failure.issue() is Database(@sqlite.DatabaseOpen(_)))
  assert_true(failure.failed_database is Some(_))
  assert_true(failure.lock is Some(_))
  assert_true(failure.root is Some(_))
  failure.retry_cleanup().unwrap()
  failure.retry_cleanup().unwrap()
  assert_true(failure.issue() is Database(@sqlite.DatabaseOpen(_)))
  let inspection = library.open_inspection_database(
    path + "/.actql-publication.sqlite3",
    4096L,
  )
  assert_eq(inspection.read("original", "input").unwrap().body, b"original")
  assert_true(inspection.inspection_status() is Err(@sqlite.DatabaseOpen(_)))
  inspection.close_checked().unwrap()
}

///|
test "Store configuration refusal starts no partial owner and keeps the primary issue" {
  let (library, path) = store_open_custody_fixture("store-open-invalid")
  let failure = match
    open_store_with_custody(
      library,
      path,
      native_payload_cid("store-open-invalid-authority"),
      -1L,
      4L,
      4096L,
      diagnostic_ceiling=Some(256),
    ) {
    Err(RefusedBeforeAcquisition(issue)) => issue
    Err(CleanupRequired(_)) => {
      fail("configuration refusal acquired cleanup responsibility")
      return
    }
    Ok(_) => {
      fail("invalid Store capacity was admitted")
      return
    }
  }
  assert_true(failure is InvalidConfiguration)
  let root = @filesystem.open_root(path).unwrap()
  assert_eq(
    root.inspect_generation(".actql-publication.sqlite3").unwrap(),
    None,
  )
  root.close().unwrap()
}

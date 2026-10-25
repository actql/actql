///|
/// Required local SQLite fixture, never an environment-missing success. Fault
/// injection is distinct from an observed kernel/SQLite close failure.
fn open_failure_fixture() -> (Library, @filesystem.Root, String) {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  (
    load_library(
      @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
      diagnostic_ceiling=Some(256),
    ).unwrap(),
    @filesystem.open_root(path).unwrap(),
    path,
  )
}

///|
#borrow(database)
extern "C" fn fail_open_cleanup(database : Database) -> Unit = "actql_native_sqlite_test_failed_open_cleanup"

///|
#borrow(database)
extern "C" fn fail_open_close(database : Database, failures : Int) -> Unit = "actql_native_sqlite_test_fail_close"

///|
#borrow(database)
extern "C" fn open_cleanup_close_count(database : Database) -> Int = "actql_native_sqlite_test_checked_close_count"

///|
test "failed SQLite open retains original handle and diagnosis through cleanup retry" {
  let (library, root, path) = open_failure_fixture()
  let selected = path + "/open-failure-custody.sqlite3"
  let original = library.open_database_with_custody(selected, 1024L).unwrap()
  original.insert("original", "input", b"e\xcc\x81\r\n").unwrap() |> ignore
  assert_true(
    original.reserve_capacity("original", "holding", 7L, 1L, 32L, 2L).unwrap(),
  )
  fail_open_close(original, 2)
  fail_open_cleanup(original)
  let failure = match sqlite_open_result_with_custody(original) {
    Err(value) => value
    Ok(_) => {
      fail("failed-open handle was admitted as a usable database")
      return
    }
  }
  assert_true(physical_equal(failure.database.unwrap(), original))
  match failure.issue() {
    DatabaseOpen(message) =>
      assert_eq(message, "injected original database open failure")
    _ => fail("original open classification changed")
  }
  assert_true(failure.retry_cleanup() is Err(Physical(_)))
  assert_true(physical_equal(failure.database.unwrap(), original))
  assert_eq(open_cleanup_close_count(original), 1)
  failure.retry_cleanup().unwrap()
  assert_true(failure.database is None)
  assert_eq(open_cleanup_close_count(original), 2)
  failure.retry_cleanup().unwrap()
  assert_eq(open_cleanup_close_count(original), 2)
  match failure.issue() {
    DatabaseOpen(message) =>
      assert_eq(message, "injected original database open failure")
    _ => fail("cleanup overwrote the original open classification")
  }
  let restored = library
    .open_existing_database_with_custody(selected, 1024L)
    .unwrap()
  assert_eq(restored.read("original", "input").unwrap().body, b"e\xcc\x81\r\n")
  let usage = restored.capacity_usage("original").unwrap()
  assert_eq(usage.reserved_bytes, 7L)
  assert_eq(usage.reserved_objects, 1L)
  restored.close_checked().unwrap()
  root.close().unwrap()
}

///|
test "existing SQLite failed-open custody does not create missing originals" {
  let (library, root, path) = open_failure_fixture()
  let name = "open-failure-missing.sqlite3"
  assert_eq(root.inspect_generation(name).unwrap(), None)
  let failure = match
    library.open_existing_database_with_custody(path + "/" + name, 1024L) {
    Err(value) => value
    Ok(_) => {
      fail("missing original database was opened")
      return
    }
  }
  assert_true(failure.issue() is DatabaseOpen(_))
  failure.retry_cleanup().unwrap()
  failure.retry_cleanup().unwrap()
  assert_true(failure.issue() is DatabaseOpen(_))
  assert_eq(root.inspect_generation(name).unwrap(), None)
  root.close().unwrap()
}

///|
test "SQLite custody API keeps positive admission and refuses invalid limits before open" {
  let (library, root, path) = open_failure_fixture()
  let name = "open-failure-limit.sqlite3"
  let failure = match
    library.open_database_with_custody(path + "/" + name, -1L) {
    Err(value) => value
    Ok(_) => {
      fail("negative SQLite limit was accepted")
      return
    }
  }
  assert_true(failure.issue() is InvalidLimit)
  assert_true(failure.database is None)
  failure.retry_cleanup().unwrap()
  assert_eq(root.inspect_generation(name).unwrap(), None)
  let accepted = library
    .open_database_with_custody(path + "/" + name, 64L)
    .unwrap()
  accepted.insert("positive", "input", b"original").unwrap() |> ignore
  assert_eq(accepted.read("positive", "input").unwrap().body, b"original")
  accepted.close_checked().unwrap()
  root.close().unwrap()
}

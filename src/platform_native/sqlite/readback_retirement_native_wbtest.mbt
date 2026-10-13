///|
#borrow(database)
extern "C" fn test_result_storage_empty(database : Database) -> Bool = "actql_native_sqlite_test_result_storage_empty"

///|
#borrow(database)
extern "C" fn test_readback_fail_close(
  database : Database,
  failures : Int,
) -> Unit = "actql_native_sqlite_test_fail_close"

///|
#borrow(database)
extern "C" fn test_readback_close_count(database : Database) -> Int = "actql_native_sqlite_test_checked_close_count"

///|
test "checked SQLite close retires readback only after success and keeps returned bytes" {
  let (library, _, path) = existing_database_fixture()
  let selected = path + "/readback-retirement.sqlite3"
  let database = library.open_database(selected, 1024L).unwrap()
  let body = b"e\xcc\x81\r\n"
  database.insert("original", "input", body).unwrap() |> ignore
  let returned = database.read("original", "input").unwrap()
  assert_false(test_result_storage_empty(database))
  test_readback_fail_close(database, 1)
  assert_true(database.close_checked() is Err(Physical(_)))
  assert_false(test_result_storage_empty(database))
  assert_eq(returned.body, body)
  assert_eq(test_readback_close_count(database), 1)
  database.close_checked().unwrap()
  assert_true(test_result_storage_empty(database))
  assert_eq(test_readback_close_count(database), 2)
  assert_eq(returned.body, body)
  database.close_checked().unwrap()
  assert_true(test_result_storage_empty(database))
  assert_eq(test_readback_close_count(database), 2)
  let reopened = library.open_existing_database(selected, 1024L).unwrap()
  assert_eq(reopened.read("original", "input").unwrap().body, body)
  reopened.close_checked().unwrap()
}

///|
test "ordinary SQLite close retires scan storage without changing returned entry" {
  let (library, _, path) = existing_database_fixture()
  let database = library
    .open_database(path + "/readback-scan-retirement.sqlite3", 1024L)
    .unwrap()
  database.insert("original", "input", b"retained").unwrap() |> ignore
  let returned = database.scan_after("original", "").unwrap()
  assert_eq(returned.key, "input")
  assert_eq(returned.body, b"retained")
  assert_false(test_result_storage_empty(database))
  database.close()
  assert_true(test_result_storage_empty(database))
  database.close()
  assert_true(test_result_storage_empty(database))
  assert_eq(returned.key, "input")
  assert_eq(returned.body, b"retained")
}

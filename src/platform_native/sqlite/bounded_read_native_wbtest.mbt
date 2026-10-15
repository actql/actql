///|
#borrow(database)
extern "C" fn bounded_readback_empty(database : Database) -> Bool = "actql_native_sqlite_test_result_storage_empty"

///|
test "bounded read exact bytes refuse before readback copy without changing original" {
  let (library, _, path) = existing_database_fixture()
  let database = library
    .open_database(path + "/bounded-read.sqlite3", 64L)
    .unwrap()
  let body = b"e\xcc\x81\r\n"
  database.insert("original", "input", body).unwrap() |> ignore
  let returned = database.read_with_body_limit("original", "input", 5L).unwrap()
  assert_eq(returned.revision, 0L)
  assert_eq(returned.body, body)
  assert_false(bounded_readback_empty(database))
  assert_true(
    database.read_with_body_limit("original", "input", 4L) is Err(BodyTooLarge),
  )
  assert_true(bounded_readback_empty(database))
  assert_eq(returned.body, body)
  assert_eq(database.read("original", "input").unwrap().body, body)
  database.close_checked().unwrap()
}

///|
test "bounded scan refuses first row without copying key body or skipping it" {
  let (library, _, path) = existing_database_fixture()
  let database = library
    .open_database(path + "/bounded-scan.sqlite3", 64L)
    .unwrap()
  database.insert("original", "a", b"12345").unwrap() |> ignore
  database.insert("original", "b", b"x").unwrap() |> ignore
  assert_true(
    database.scan_after_with_body_limit("original", "", 4L) is Err(BodyTooLarge),
  )
  assert_true(bounded_readback_empty(database))
  let first = database.scan_after_with_body_limit("original", "", 5L).unwrap()
  assert_eq(first.key, "a")
  assert_eq(first.revision, 0L)
  assert_eq(first.body, b"12345")
  let second = database.scan_after_with_body_limit("original", "a", 1L).unwrap()
  assert_eq(second.key, "b")
  assert_eq(second.body, b"x")
  assert_true(
    database.scan_after_with_body_limit("original", "b", 0L) is Err(NotFound),
  )
  assert_true(bounded_readback_empty(database))
  database.close_checked().unwrap()
}

///|
test "bounded zero permits empty bodies but never a nonempty one" {
  let (library, _, path) = existing_database_fixture()
  let database = library
    .open_database(path + "/bounded-zero.sqlite3", 64L)
    .unwrap()
  database.insert("original", "a", b"").unwrap() |> ignore
  database.insert("original", "b", b"x").unwrap() |> ignore
  assert_eq(
    database.read_with_body_limit("original", "a", 0L).unwrap().body,
    b"",
  )
  assert_eq(
    database.scan_after_with_body_limit("original", "", 0L).unwrap().key,
    "a",
  )
  assert_true(
    database.read_with_body_limit("original", "b", 0L) is Err(BodyTooLarge),
  )
  assert_true(
    database.scan_after_with_body_limit("original", "a", 0L)
    is Err(BodyTooLarge),
  )
  assert_true(bounded_readback_empty(database))
  database.close_checked().unwrap()
}

///|
test "bounded read never raises original database bound or changes its refusal" {
  let (library, _, path) = existing_database_fixture()
  let selected = path + "/bounded-database-limit.sqlite3"
  let writer = library.open_database(selected, 64L).unwrap()
  writer.insert("original", "input", b"12345").unwrap() |> ignore
  writer.close_checked().unwrap()
  let database = library.open_existing_database(selected, 4L).unwrap()
  assert_true(database.read("original", "input") is Err(Physical(_)))
  assert_true(
    database.read_with_body_limit("original", "input", 64L) is Err(Physical(_)),
  )
  assert_true(
    database.scan_after_with_body_limit("original", "", 64L) is Err(Physical(_)),
  )
  assert_true(bounded_readback_empty(database))
  database.close_checked().unwrap()
}

///|
test "bounded reads preserve transaction rollback missing and invalid refusals" {
  let (library, _, path) = existing_database_fixture()
  let database = library
    .open_database(path + "/bounded-transaction.sqlite3", 64L)
    .unwrap()
  database.begin_immediate().unwrap()
  database.insert("original", "input", b"12345").unwrap() |> ignore
  assert_true(
    database.read_with_body_limit("original", "input", 4L) is Err(BodyTooLarge),
  )
  assert_eq(
    database.read_with_body_limit("original", "input", 5L).unwrap().body,
    b"12345",
  )
  database.rollback().unwrap()
  assert_true(
    database.read_with_body_limit("original", "input", 64L) is Err(NotFound),
  )
  assert_true(
    database.read_with_body_limit("original", "input", -1L) is Err(InvalidLimit),
  )
  assert_true(
    database.scan_after_with_body_limit("original", "", -1L)
    is Err(InvalidLimit),
  )
  assert_true(
    database.read_with_body_limit("", "input", 64L) is Err(InvalidName),
  )
  assert_true(
    database.scan_after_with_body_limit("original", "x".repeat(513), 64L)
    is Err(InvalidName),
  )
  database.close_checked().unwrap()
  assert_true(
    database.read_with_body_limit("original", "input", 64L)
    is Err(DatabaseClosed),
  )
  assert_true(
    database.scan_after_with_body_limit("original", "", 64L)
    is Err(DatabaseClosed),
  )
}

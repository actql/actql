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

///|
test "observed scan copies exact extent without raising legacy read limits" {
  let (library, _, path) = existing_database_fixture()
  let database = library
    .open_database(path + "/observed-scan.sqlite3", 4L)
    .unwrap()
  database.insert_with_body_extent("original", "a", b"12345", 5L).unwrap()
  |> ignore
  let (key, header) = database.observe_scan_body_extent("original", "").unwrap()
  assert_eq(key, "a")
  assert_eq(header.body_bytes, 5L)
  let row = database
    .scan_exact_body_extent("original", "", key, header)
    .unwrap()
  assert_eq(row.body, b"12345")
  assert_true(database.scan_after("original", "") is Err(Physical(_)))
  assert_true(bounded_readback_empty(database))
  assert_true(
    database.scan_exact_body_extent("original", "", key, {
      revision: 0L,
      body_bytes: 4L,
    })
    is Err(Collision),
  )
  assert_true(bounded_readback_empty(database))
  assert_true(
    database.scan_exact_body_extent("original", "", "b", header)
    is Err(Collision),
  )
  assert_true(bounded_readback_empty(database))
  database.close_checked().unwrap()
}

///|
test "observed scan refuses newly inserted predecessor instead of skipping it" {
  let (library, _, path) = existing_database_fixture()
  let database = library
    .open_database(path + "/observed-predecessor.sqlite3", 64L)
    .unwrap()
  database.insert("original", "b", b"old").unwrap() |> ignore
  let (key, header) = database.observe_scan_body_extent("original", "").unwrap()
  database.insert("original", "a", b"new").unwrap() |> ignore
  assert_true(
    database.scan_exact_body_extent("original", "", key, header)
    is Err(Collision),
  )
  assert_true(bounded_readback_empty(database))
  assert_eq(database.scan_after("original", "").unwrap().key, "a")
  database.close_checked().unwrap()
}

///|
test "observed scan refuses stale revision and preserves transaction rollback" {
  let (library, _, path) = existing_database_fixture()
  let database = library
    .open_database(path + "/observed-revision.sqlite3", 64L)
    .unwrap()
  database.insert("original", "a", b"old").unwrap() |> ignore
  let (key, header) = database.observe_scan_body_extent("original", "").unwrap()
  database.begin_immediate().unwrap()
  database.compare_exchange("original", "a", 0L, b"new-longer").unwrap()
  |> ignore
  assert_true(
    database.scan_exact_body_extent("original", "", key, header)
    is Err(Collision),
  )
  assert_true(bounded_readback_empty(database))
  database.rollback().unwrap()
  assert_eq(
    database.scan_exact_body_extent("original", "", key, header).unwrap().body,
    b"old",
  )
  database.close_checked().unwrap()
}

///|
#borrow(database)
extern "C" fn observed_scan_body_text(database : Database) -> Bool = "actql_native_sqlite_test_body_text"

///|
test "observed scan rejects changed storage type before copying body" {
  let (library, _, path) = existing_database_fixture()
  let database = library
    .open_database(path + "/observed-type.sqlite3", 64L)
    .unwrap()
  database.insert("original", "a", b"old").unwrap() |> ignore
  let (key, header) = database.observe_scan_body_extent("original", "").unwrap()
  assert_true(observed_scan_body_text(database))
  assert_true(
    database.scan_exact_body_extent("original", "", key, header)
    is Err(Physical(_)),
  )
  assert_true(bounded_readback_empty(database))
  assert_true(
    database.observe_scan_body_extent("original", "") is Err(Physical(_)),
  )
  assert_true(bounded_readback_empty(database))
  database.close_checked().unwrap()
}

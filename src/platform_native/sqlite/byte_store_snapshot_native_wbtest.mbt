///|
test "original row header keeps absent empty bytes revision and body bound without body copy" {
  let (library, _, root) = existing_database_fixture()
  let path = root + "/byte-header.sqlite3"
  let database = library.open_database(path, 64L).unwrap()
  assert_true(database.read_header("原", "missing") is Err(NotFound))
  database.insert("原", "e\u0301/😀", b"\xe9\x9b\xaa\x00\n").unwrap()
  |> ignore
  database.insert("原", "empty", b"").unwrap() |> ignore
  let header = database.read_header("原", "e\u0301/😀").unwrap()
  assert_eq(header.revision, 0L)
  assert_eq(header.body_bytes, 5L)
  assert_true(bounded_readback_empty(database))
  let empty = database.read_header("原", "empty").unwrap()
  assert_eq(empty.body_bytes, 0L)
  assert_eq(empty.revision, 0L)
  assert_true(bounded_readback_empty(database))
  database.compare_exchange("原", "empty", 0L, b"x").unwrap() |> ignore
  let replaced = database.read_header("原", "empty").unwrap()
  assert_eq(replaced.revision, 1L)
  assert_eq(replaced.body_bytes, 1L)
  let bounded = library.open_existing_database(path, 4L).unwrap()
  assert_true(bounded.read_header("原", "e\u0301/😀") is Err(Physical(_)))
  assert_true(bounded_readback_empty(bounded))
  bounded.close_checked().unwrap()
  database.close_checked().unwrap()
  assert_true(database.read_header("原", "empty") is Err(DatabaseClosed))
}

///|
test "deferred observation keeps its original snapshot without acquiring another writer or committing" {
  let (library, _, root) = existing_database_fixture()
  let path = root + "/byte-deferred.sqlite3"
  let writer = library.open_database(path, 64L).unwrap()
  writer.insert("原", "row", b"before").unwrap() |> ignore
  let reader = library.open_existing_database(path, 64L).unwrap()
  reader.begin_deferred().unwrap()
  assert_eq(reader.read_header("原", "row").unwrap().revision, 0L)
  writer.begin_immediate().unwrap()
  writer.compare_exchange("原", "row", 0L, b"after").unwrap() |> ignore
  writer.commit().unwrap()
  assert_eq(reader.read_header("原", "row").unwrap().revision, 0L)
  assert_eq(reader.read("原", "row").unwrap().body, b"before")
  assert_true(reader.transaction_state() is Ok(ActiveSqliteTransaction))
  reader.rollback().unwrap()
  assert_eq(reader.read_header("原", "row").unwrap().revision, 1L)
  assert_eq(reader.read("原", "row").unwrap().body, b"after")
  reader.close_checked().unwrap()
  assert_true(reader.begin_deferred() is Err(DatabaseClosed))
  writer.close_checked().unwrap()
}
